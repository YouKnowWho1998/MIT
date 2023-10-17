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

//===============================================================================================================
module mkTranslator(WideMem mem, Cache ifc);//接收一些DDR3接口(例如WideMem),并返回一个cache接口

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
//===============================================================================================================































