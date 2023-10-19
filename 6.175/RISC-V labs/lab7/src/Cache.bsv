import CacheTypes::*;
import MemUtil::*;
import Fifo::*;
import Vector::*;
import Types::*;
import MemTypes::*;

// interface WideMem;
//     method Action req(WideMemReq r);
//     method ActionValue#(CacheLine) resp;
// endinterface

// interface Cache;
//     method Action req(MemReq r);
//     method ActionValue#(MemResp) resp;
// endinterface


//======================================= Translator ======================================================================
module mkTranslator(WideMem mem, Cache ifc);//接收DDR3接口(例如WideMem类型),并返回一个cache接口

    //从PC地址中剥离出offset数 这个offset就是选择阵列中第几个word值输出
    function CacheWordSelect getOffset(Addr addr) = truncate(addr >> 2);
    Fifo#(2, MemReq) pendLdReq <- mkCFFifo;

    //如果是load请求 才将此条请求加载到FIFO中
    method Action req(MemReq r);
        if (r.op == Ld) begin
            pendLdReq.enq(r);
        end
        //调用toWideMemReq函数 把这条MemReq请求(Cache)转换成WideMemReq请求(DDR3)
        mem.req(toWideMemReq(r));
    endmethod

    method ActionValue#(MemResp) resp;
        //将FIFO中的请求取回并弹出FIFO
        let request = pendLdReq.first;
        pendLdReq.deq;

        let cacheLine <- mem.resp;
        //根据请求中的PC地址剥离出offset数
        let offset = getOffset(request.addr);
        //选择cacheline阵列中的第offset个字输出(输出的是指令和数据，都是32位)
        return cacheLine[offset];
    endmethod
endmodule
//================================================================================================================



//================================================== Cache =========================================================================
// Cache的工作流程：
//   1.CPU向Cache发出访存请求
//   2.Cache根据请求地址的tag位，若命中，则跳转到第7步
//   3.若要替换一个Cache块，则根据替换算法选择一个cache块
//   4.若该块是Dirty的，则还需将这个块先写回内存
//   5.再读出CPU访存请求所在的数据块（内存中）
//   6.将该数据块写入对应cache块中，更新其元数据（valid位和tag位统称元数据）
//   7.执行CPU的访存请求

typedef enum{//定义状态机变量
	Ready,
	StartMiss,
	SendFillReq,
	WaitFillResp
} ReqStatus deriving (Bits,Eq);


module mkCache(WideMem mem, Cache ifc);
    
    //一个cache块由data部分, tag部分, dirty部分组成, 多个cache块组成SRAM
    Vector#(CacheRows, Reg#(CacheLine))        dataArray   <- replicateM(mkRegU);//例化data部分cache阵列
    Vector#(CacheRows, Reg#(Maybe#(CacheTag))) tagArray    <- replicateM(mkRegU);//例化tag部分cache阵列
    Vector#(CacheRows, Reg#(Bool))             dirtyArray  <- replicateM(mkRegU);//例化dirty部分cache阵列

    Fifo#(1,Data)	hitF 	<- mkBypassFifo;//是否命中状态
	Reg#(MemReq)	missReq	<- mkRegU;      //未命中指令的地址
	Reg#(ReqStatus)	state	<- mkReg(Ready);//状态机

//-------------------------------------------Function函数--------------------------------------------------------------------------------
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

//------------------------------------------StartMiss状态-------------------------------------------------------------------------------------------
    rule startMiss(state == StartMiss);
        let idx	  = getIndex(missReq.addr); //从未命中指令的地址中截取Inedx片段
		let tag	  = tagArray[idx];  //Index片段用来选择SRAM中的哪一个Cache块
		let dirty = dirtyArray[idx];//选定未命中指令的目的Cache块

        //如果这个Cache块是Dirty的 意思被CPU写过 不再是内存中的副本了
        //则还需要先把这个Cache块中的数据写回内存
        if (isValid(tag) && dirty) begin 
            let addr = {fromMaybe(?, tag), idx, 6'b0};
            let data = dataArray[idx];
            mem.req(WideMemReq{
                write_en:'1,
				addr:addr,
				data:data
            });
        end
        state <= SendFillReq;
    endrule
//----------------------------------------SendFillReq状态-------------------------------------------------------
    rule sendFillReq(state == SendFillReq);
		WideMemReq request = toWideMemReq(missReq);//转换成WideMemReq结构体
		Bit#(CacheLineWords) write_en = 0;//只向内存中写入 为0代表写入内存 为1代表读取内存
		request.write_en = write_en;
		mem.req(request);
		state <= WaitFillResp;
	endrule
//----------------------------------------WaitFillResp状态--------------------------------------------------
    rule waitFillResp(state == WaitFillResp);
        let idx		  =  getIndex(missReq.addr);
		let tag		  =  getTag(missReq.addr);
		let offset	  =  getOffset(missReq.addr);
		let data	  <- mem.resp; //内存响应读取 
        tagArray[idx] <= tagged Valid tag; //更新元数据
    
        //当Cache里未命中时 当然要从内存里读取数据到Cache中了 然后CPU再读取Cache中的数据
        if (missReq.op == Ld) begin 
            dirtyArray[idx]	<= False;//Dirty位变低电平(clean) 代表CPU没有读写过 是内存数据的副本
            dataArray[idx]	<= data; //如果未命中指令是Load指令 则将data写入对应的Cache块中 
            hitF.enq(data[offset]);   //Cache已经更新 可以输出命中的数据
        end    
        else begin
            //如果不是load命令 则选中data[offset]接收内存传输的数据
            //offset偏移量控制选中cache块中的哪个word 一个cache块(CacheLine)有16个word
            data[offset]	=  missReq.data;
			dirtyArray[idx]	<= True;
			dataArray[idx]	<= data;
        end
        state <= Ready;
    endrule
//---------------------------------------------------------------------------------------------------------
    method Action req(MemReq r) if(state == Ready);
        let idx	   = getIndex(r.addr);
        let offset = getOffset(r.addr);
        let tag    = getTag(r.addr);
        //只要对应Cache块是Valid 就将输入指令的tag片段传入覆盖(代表命中)
        let hit	   = (isValid(tagArray[idx])) ? (fromMaybe(?, tagArray[idx]) == tag) : False;
        
		if (hit) begin
			let cacheLine = dataArray[idx];
			if (r.op == Ld) begin 
				hitF.enq(cacheLine[offset]);
			end 
            else begin
				cacheLine[offset] =  r.data;
				dataArray[idx]	  <= cacheLine;
				dirtyArray[idx]	  <= True; //被CPU写过了置高电平
			end
		end 
        else begin
			missReq <= r; //如果没有命中 则进入StartMiss状态 
			state   <= StartMiss;
		end
//---------------------------------------------------------------------------------------------------------
    method ActionValue#(Data) resp;
        hitF.deq;
        return hitF.first;
    endmethod
//---------------------------------------------------------------------------------------------------------

endmodule
