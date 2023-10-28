import CacheTypes::*;
import Fifo::*;

// cache <-> mem message
// typedef struct{
//     CoreID            child; 
//     Addr              addr;
//     MSI               state;
//     Maybe#(CacheLine) data;
// } CacheMemResp deriving(Eq, Bits, FShow);

// typedef struct{
//     CoreID      child;
//     Addr        addr;
//     MSI         state;
// } CacheMemReq deriving(Eq, Bits, FShow);

// typedef union tagged { //标签联合体
//     CacheMemReq     Req;
//     CacheMemResp    Resp;
// } CacheMemMessage deriving(Eq, Bits, FShow);

// interface MessageFifo#( numeric type n );
//     method Action enq_resp( CacheMemResp d );
//     method Action enq_req( CacheMemReq d );
//     method Bool hasResp;
//     method Bool hasReq;
//     method Bool notEmpty;
//     method CacheMemMessage first;
//     method Action deq;
// endinterface

//========================================================================================================================
module mkMessageFifo(MessageFifo#(n));
    //例化生成对应enq_resp和enq_req的接口FIFO
    Fifo#(2, CacheMemReq)  req_fifo  <- mkCFFifo;
    Fifo#(2, CacheMemResp) resp_fifo <- mkCFFifo;

//---------------------------------------------------------------------------------------------------------------------------------
    method Action enq_resp(CacheMemResp d);
        resp_fifo.enq(d);
    endmethod
//--------------------------------------------------------------------------------------------------------------------------------
    method Action enq_req(CacheMemReq d);
        req_fifo.enq(d);
    endmethod
//--------------------------------------------------------------------------------------------------------------------------------
    //hasResp和hasReq是用来指示resp_fifo和req_fifo是否有数据的标识位
    //notEmpty是两个标识位的或
    method Bool hasResp = resp_fifo.notEmpty; 
    method Bool hasReq  = req_fifo.notEmpty; 
    method Bool notEmpty = (resp_fifo.notEmpty || req_fifo.notEmpty); 
//--------------------------------------------------------------------------------------------------------------------------------
    //如果resp_fifo有数据则输出它 如req_fifo有数据则输出它
    method CacheMemMessage first; 
        if (resp_fifo.notEmpty) begin
            return tagged Resp resp_fifo.first;
        end
        else begin
            return tagged Req req_fifo.first;
        end
    endmethod
//--------------------------------------------------------------------------------------------------------------------------------
    method Action deq;
        if (resp_fifo.notEmpty) begin
            resp_fifo.deq;      
        end
        else begin
            req_fifo.deq;
        end
    endmethod
//--------------------------------------------------------------------------------------------------------------------------------

endmodule
//========================================================================================================================