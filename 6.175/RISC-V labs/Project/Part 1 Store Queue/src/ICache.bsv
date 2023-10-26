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

//================================================= ICache =========================================================================

typedef enum{//定义Cache状态机变量
	Ready,
	StartMiss,
	SendFillReq,
	WaitFillResp
} CacheStatus deriving (Bits,Eq);


module mkICache(WideMem mem, ICache ifc);
    
    //一个cache块由data部分, tag部分, dirty部分组成, 多个cache块组成SRAM
    Vector#(CacheRows, Reg#(CacheLine))        dataArray   <- replicateM(mkRegU);//例化data部分阵列
    Vector#(CacheRows, Reg#(Maybe#(CacheTag))) tagArray    <- replicateM(mkReg(Invalid));//例化tag部分阵列
    Vector#(CacheRows, Reg#(Bool))             dirtyArray  <- replicateM(mkReg(False));//例化dirty部分阵列

    Fifo#(2, Data)	    hitQ 	 <- mkBypassFifo;//是否命中状态
    Reg#(Addr)          missAddr <- mkRegU;      //未命中指令地址
    Fifo#(2, MemReq)    memReqQ  <- mkCFFifo;    //内存传入队列 存储的是请求数据结构体
    Fifo#(2, CacheLine) memRespQ <- mkCFFifo;    //内存传出队列 存储的是Cache块的data部分
	Reg#(CacheStatus)   state    <- mkReg(Ready);//状态机

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
    function CacheTag getTag(Addr addr) = truncateLSB(addr);
//-------------------------------------------------------------------------------------------------------------------------------------------------------
    rule sendFillReq(state == StartMiss);
        //如果是指令未命中 向内存请求更新未命中指令
        memReqQ.enq(MemReq{op: Ld, addr: missAddr, data:?});
        state <= WaitFillResp;
    endrule
//-------------------------------------------------------------------------------------------------------------------------------------------------------
    rule waitFillResp(state == WaitFillResp);
        //获取未命中指令的tag index sel(offset)
        CacheWordSelect sel = getOffset(missAddr);
        CacheIndex idx = getIndex(missAddr);
        CacheTag tag = getTag(missAddr);
        //内存响应请求 传入了Cache未命中指令的内容
        let line = memRespQ.first;
        //根据index 选择Cache块进行更新 把tag位变成valid
        dataArray[idx] <= line;        
        tagArray[idx] <= tagged Valid tag;
        //根据sel(offset) 选择传出Cache块中的哪个字
        hitQ.enq(line[sel]);
        //弹出内存传出队列并完成“指令未命中”操作
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
    method Action req(Addr a) if(state == Ready);
        //正常指令命中情况下的流程
        CacheWordSelect sel = getOffset(a);
        CacheIndex idx = getIndex(a);
        CacheTag tag = getTag(a);

        //当传入Cache的指令index选中的Cache块Tag位是Valid时 表示命中
        //命中立刻根据idx和sel(offset)选中具体的字传入处理器中
        if (tagArray[idx] matches tagged Valid .currTag &&& currTag == tag) begin
            hitQ.enq(dataArray[idx][sel]);
        end
        //如果没有命中则切换至"未命中指令"流程
        else begin
            missAddr <= a;
            state <= StartMiss;
        end
    endmethod
//-------------------------------------------------------------------------------------------------------------------------------------------------------
    method ActionValue#(Data) resp;
        hitQ.deq;
        return hitQ.first;
    endmethod
//-------------------------------------------------------------------------------------------------------------------------------------------------------
endmodule