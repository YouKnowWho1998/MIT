import CacheTypes::*;
import Types::*;
import ProcTypes::*;
import Fifo::*;
import Vector::*;
import MemTypes::*;
import MemUtil::*;
import SimMem::*;

// Cache的工作流程：
//   1.CPU向Cache发出访存请求
//   2.Cache根据请求地址的tag位，若命中，则跳转到第7步
//   3.若要替换一个Cache块，则根据替换算法选择一个cache块
//   4.若该块是Dirty的，则还需将这个块先写回内存
//   5.再读出CPU访存请求所在的数据块（内存中）
//   6.将该数据块写入对应cache块中，更新其元数据（valid位和tag位统称元数据）
//   7.执行CPU的访存请求

typedef enum{//定义Cache状态机变量
	Ready,
	StartMiss,
	SendFillReq,
	WaitFillResp
} CacheStatus deriving (Bits,Eq);

//================================================= DCache ======================================================================================

module mkDCache(WideMem mem, Cache ifc);
    
    //一个cache块由data部分, tag部分, dirty部分组成, 多个cache块组成SRAM
    Vector#(CacheRows, Reg#(CacheLine))        dataArray   <- replicateM(mkRegU);//例化data部分阵列
    Vector#(CacheRows, Reg#(Maybe#(CacheTag))) tagArray    <- replicateM(mkReg(Invalid));//例化tag部分阵列
    Vector#(CacheRows, Reg#(Bool))             dirtyArray  <- replicateM(mkReg(False));//例化dirty部分阵列

    Fifo#(2, Data)	    hitQ 	 <- mkBypassFifo;//是否命中状态
    Fifo#(1, MemReq)    reqQ     <- mkBypassFifo;//来自处理器的所有请求将首先进入reqQ队列
    Reg#(Addr)          missAddr <- mkRegU;      //未命中指令地址
    Fifo#(2, MemReq)    memReqQ  <- mkCFFifo;    //内存传入队列 存储的是请求数据结构体
    Fifo#(2, CacheLine) memRespQ <- mkCFFifo;    //内存传出队列 存储的是Cache块的data部分
	Reg#(CacheStatus)   state    <- mkReg(Ready);//Cache状态机

//-------------------------------------------Function-----------------------------------------------------------------------------------
    // typedef struct{
    //     MemOp op;
    //     Addr  addr;
    //     Data  data;
    // } MemReq deriving(Eq, Bits, FShow);

    // typedef struct{
    //     Bit#(CacheLineWords) write_en;  // Word write enable
    //     Word                 addr;
    //     CacheLine            data;      // Vector#(CacheLineWords, Word)
    // } WideMemReq deriving(Eq,Bits);

    //截取Index片段
	function CacheIndex getIndex(Addr addr)	= truncate(addr >> 6);
    
    //截取Offset片段
    function CacheWordSelect getOffset(Addr addr) = truncate(addr >> 2);
    
    //截取Tag片段
    function CacheTag getTag(Addr addr) = truncateLSB(addr)
//-------------------------------------------------------------------------------------------------------------------------------------------------------
    rule startMiss (state == StartMiss);
        //根据未命中地址获取sel(offset), index, tag, dirty
        CacheWordSelect sel = getOffset(missReq.addr);
        CacheIndex idx = getIndex(missReq.addr);
        CacheTag tag = tagArray[idx];
        Bool dirty = dirtyArray[idx];

        //如果tag位和dirty位都为1，则还需要将此Cache块数据传入内存
        if (isValid(tag) && dirty) begin
            let addr = {tag, idx, sel, 2'b0};
            memReqQ.enq(MemReq{op: St, addr: addr, data:?});
        end
        state <= SendFillReq;
//-------------------------------------------------------------------------------------------------------------------------------------------------------
    rule sendFillResp (state == SendFillResp);
        //如果dirty位不是1，则向内存请求传入未命中指令地址的数据    
        memReqQ.enq(MemReq{op: Ld, addr: missReq.addr, data:?});
        state <= WaitFillResp;
    endrule
//-------------------------------------------------------------------------------------------------------------------------------------------------------
    rule waitFillResp (state == WaitFillResp);
        //获取未命中指令的tag index sel(offset)
        CacheWordSelect sel = getOffset(missAddr);
        CacheIndex idx = getIndex(missAddr);
        CacheTag tag = getTag(missAddr);

        //内存响应请求 传入了Cache未命中指令的内容
        let line = memRespQ.first;

        //根据index 选择Cache块进行更新 把tag位变成valid
        tagArray[idx] <= tagged Valid tag;

        //如果处理器访存指令是Load读取 则将内存传入数据传给处理器
        //如果不是Load指令 则处理器会写入新数据到Cache中
        if(missReq.addr == Ld) begin
            dirtyArray[idx] <= False;//处理器只有写入Cache了 dirty位才会True
            hitQ.enq(line[sel]);
        end
        else begin
            dirtyArray[idx] <= True;
            line[sel] = missReq.data;
        end

        dataArray[idx] <= line;        
        memRespQ.deq;
        state <= Ready;
    endrule
//-------------------------------------------------------------------------------------------------------------------------------------------------------
    rule sendToMemory;
        //Cache向内存请求传入数据 
        memReqQ.deq;
        let r = memReqQ.first;

        //获得传入指令r的index 再根据index选择哪个Cache块的数据传入
        CacheIndex idx = getIndex(r.addr);
        CacheLine line = dataArray[idx];

        Bit#(CacheLineWords) en;
        //如果是Store命令 则使能全为1 将整个Cache块数据传入内存中
        if (r.op == St) begin
            en = '1;
        end
        else begin
            en = '0;
        end

        //通过真实内存接口传入
        mem.req(WideMemReq{
            write_en: en,
            addr: r.addr,
            data: line
        });
    endrule
//-------------------------------------------------------------------------------------------------------------------------------------------------------
    rule getFromMemory;
        //获得内存传入的数据line并存入内存传出队列中
        let line <- mem.resp();
        memRespQ.enq(line);
    endrule
//-------------------------------------------------------------------------------------------------------------------------------------------------------
    rule doReq (state == Ready);
        //来自处理器的所有指令请求都会先进入reqQ队列中 本规则对其进行处理
        MemReq r = reqQ.first;
        reqQ.deq;
        CacheWordSelect sel = getOffset(r.addr);
        CacheIndex idx = getIndex(r.addr);
        CacheTag tag = getTag(r.addr);

        //当传入Cache的指令index选中的Cache块Tag位是Valid时 表示命中
        Bool hit = (tagArray[idx] matches tagged Valid .currTag &&&
                    (currTag == tag)) ? True : False;

        //如果指令请求是Load指令 若命中则将具体Cache块中数据传给处理器 若不中则跳转到未命中状态
        //如果不是Load指令 若命中则将请求数据写入具体Cache块中 若不中则跳转到未命中状态
        if (r.op == Ld) begin
            if (hit) begin
                hitQ.enq(dataArray[idx][sel]);
            end
            else begin
                missAddr <= a;
                status <= StartMiss;                
            end
        end
        else begin
            if (hit) begin
                dataArray[idx][sel] = r.data;
                dirtyArray[idx] = True;
            end
            else begin
                missAddr <= a;
                status <= StartMiss;                
            end
        end
    endrule
//-------------------------------------------------------------------------------------------------------------------------------------------------------
    method Action req(MemReq r) 
        reqQ.enq(r);
    endmethod
//-------------------------------------------------------------------------------------------------------------------------------------------------------
    method ActionValue#(Data) resp;
        hitQ.deq;
        return hitQ.first;
    endmethod
//-------------------------------------------------------------------------------------------------------------------------------------------------------
endmodule

//================================================= DCacheStQ ===============================================================================================================
