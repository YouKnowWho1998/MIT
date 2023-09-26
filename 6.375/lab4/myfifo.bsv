import Ehr::*;
import Vector::*;


interface Fifo#(numeric type n, type t);
    method Action enq(t x);
    method Action deq;
    method Action clear;
    method Bool notFull ;
    method Bool notEmpty ;    
    method t first;
endinterface


//=============================================================================================================
//练习1：

module mkMyConflictFifo(Fifo#(n, t)) //n是FIFO容量 t是存储数据类型
    provisos (Bits#(t,tSz)); //补充t派生自Bits类型 tSz为位宽   
    Vector#(n, Reg#(t))  data         <- replicateM(mkRegU()); //全部用寄存器构建
    Reg#(Bit#(TLog#(n))) enqP         <- mkReg(0);
    Reg#(Bit#(TLog#(n))) deqP         <- mkReg(0);
    Reg#(Bool)           notEmpty     <- mkReg(False);
    Reg#(Bool)           notFull      <- mkReg(True);

    Bit#(TLog#(n)) size = fromInteger(valueOf(n) - 1); //FIFO容量标注

    method Action enq(t x) if(notFull);
        data[enqP] <= x;
        notEmpty  <= True;        
        let enqPnext = enqP + 1'b1;
        if(enqPnext > size) begin
            enqP <= 'b0;
        end
        if(enqPnext == deqP) begin
            notFull  <= False;
        end
        enqP <= enqPnext;
    endmethod

    method Action deq if(notEmpty );
        notFull  <= True;
        let deqPnext = deqP + 1'b1;
        if(deqPnext == enqP) begin
            notEmpty  <= False;
        end
        if(deqPnext > size) begin
            deqP <= 'b0;
        end
        deqP <= deqPnext;
    endmethod

    method Bool notFull ();
        return notFull ;
    endmethod

    method Bool notEmpty ();
        return notEmpty ;
    endmethod

    method t first() if(notEmpty);
        return data[deqP];
    endmethod
endmodule


//=============================================================================================================
//练习2：

// {notnotEmpty , first, deq} < {notnotFull , enq} < clear  FIFO满可同时触发 deq < enq

module mkMyPipelineFifo(Fifo#(n, t))
    provisos (Bits#(t, tSz));
    Vector#(n, Reg#(t))  data           <- replicateM(mkRegU);
    Reg#(Bit#(TLog#(n))) enqP[3]        <- mkCReg(3, 0);
    Reg#(Bit#(TLog#(n))) deqP[3]        <- mkCReg(3, 0);
    Reg#(Bool)           notEmpty[3]    <- mkCReg(3, True);
    Reg#(Bool)           notFull[3]     <- mkCReg(3, False);

    Bit#(TLog#(n))  size  = fromInteger(valueOf(n) - 1);

    method Bool notFull (); 
        return notFull [1]; 
    endmethod

    method Bool notEmpty ();
        return notEmpty [0];
    endmethod

    method Action enq(t x) if(notFull [1]);
        data[enqP[1]] <= x;
        notEmpty [1] <= True;        
        let enqPnext = enqP[1] + 1'b1;
        if(enqPnext > size) begin
            enqP[1] <= 'b0;
        end
        if(enqPnext == deqP[1]) begin
            notFull [1] <= False;
        end
        enqP[1] <= enqPnext;
    endmethod

    method Action deq if(notEmpty [0]);
        notnotFull [0] <= True;
        let deqPnext = deqP[0] + 1'b1;
        if(deqPnext == enqP[0]) begin
            notEmpty [0] <= False;
        end
        if(deqPnext > size) begin
            deqP[0] <= 'b0;
        end
        deqP[0] <= deqPnext;
    endmethod

    method t first() if(notEmpty [0]);
        return data[deqP[0]];
    endmethod

    method Action clear();
        deqP[2] <= 0;
        enqP[2] <= 0;
        notEmpty [2] <= False;
        notFull [2] <= True;
    endmethod
endmodule



// {notnotFull , enq} < {notnotEmpty , first, deq} < clear
module mkMyBypassFifo( Fifo#(n, t) ) 
    provisos (Bits#(t, tSz));
    Vector#(n, Reg#(t))  data           <- replicateM(mkRegU);
    Reg#(Bit#(TLog#(n))) enqP[3]        <- mkCReg(3, 0);
    Reg#(Bit#(TLog#(n))) deqP[3]        <- mkCReg(3, 0);
    Reg#(Bool)           notEmpty[3]    <- mkCReg(3, True);
    Reg#(Bool)           notFull[3]     <- mkCReg(3, False);

    Bit#(TLog#(n))  size = fromInteger(valueOf(n)-1);

    method Bool notFull (); 
        return notFull [0]; 
    endmethod

    method Bool notEmpty ();
        return notEmpty [1];
    endmethod

    method Action enq(t x) if(notFull [0]);
        data[enqP[0]] <= x;
        notEmpty [0] <= True;        
        let enqPnext = enqP[0] + 1'b1;
        if(enqPnext > size) begin
            enqP[0] <= 'b0;
        end
        if(enqPnext == deqP[0]) begin
            notFull [0] <= False;
        end
        enqP[0] <= enqPnext;
    endmethod

    method Action deq if(notEmpty [1]);
        notFull [1] <= True;
        let deqPnext = deqP[1] + 1'b1;
        if(deqPnext == enqP[1]) begin
            notEmpty [1] <= False;
        end
        if(deqPnext > size) begin
            deqP[1] <= 'b0;
        end
        deqP[1] <= deqPnext;
    endmethod

    method t first() if(notEmpty [1]);
        return data[deqP[1]];
    endmethod

    method Action clear();
        deqP[2] <= 0;
        enqP[2] <= 0;
        notEmpty [2] <= False;
        notFull [2] <= True;
    endmethod
endmodule


//=============================================================================================================
//练习3 & 4：

// {notnotFull , enq} CF {notnotEmpty , first, deq}
// {notnotFull , enq, notnotEmpty , first, deq} < clear
module mkMyCFFifo( Fifo#(n, t) ) 
    provisos (Bits#(t, tSz));
    Vector#(n, Reg#(t))     data     <- replicateM(mkRegU());
    Ehr#(2, Bit#(TLog#(n))) enqP     <- mkEhr(0);
    Ehr#(2, Bit#(TLog#(n))) deqP     <- mkEhr(0);
    Ehr#(2, Bool)           notEmpty <- mkEhr(False);
    Ehr#(2, Bool)           notFull  <- mkEhr(True);
    Ehr#(2, Bool)           req_deq  <- mkEhr(False);
    Ehr#(2, Maybe#(t))      req_enq  <- mkEhr(tagged Invalid);

    Bit#(TLog#(n)) size = fromInteger(valueOf(n)-1);

    (*no_implicit_conditions, fire_when_enabled*)
    rule canonicalize;
        let enqPnext = enqP[0] + 1;
        let deqPnext = deqP[0] + 1;
        if( isValid(req_enq[1]) && notEmpty[0] &&
                    req_deq[1] && notFull[0]) begin// enq and deq
            data[enqP[0]] <= req_enq[1];         
            enqP[0] <= enqPnext;
            deqP[0] <= deqPnext;
        end 
        else if(notEmpty[0] && req_deq[1]) begin //deq only
            if(deqPnext == enqP[0]) begin
                notEmpty <= False;
            end
            notFull <= True;
            deqP[0] <= deqPnext;
        end
        else if(notFull[0] && isValid(req_enq[1])) begin //enq only
            if(enqPnext == deqP[0]) begin
                notFull <= False;
            end
            notEmpty <= True;
            enqP[0] <= enqPnext;
        end
        req_enq[1] <= tagged Invalid;
        req_deq[1] <= False; //每次执行完一次规范化规则后都需要将两个请求信号复原
    endrule 

    method Bool notFull();
        return notFull[0];
    endmethod

    method Bool notEmpty();
        return notEmpty[0];
    endmethod

    method Action clear();
        enqP[1] <= 0;
        deqP[1] <= 0;
        notEmpty[1] <= False;
        notFull[1] <= True;
    endmethod

    method Action enq(t x) if(notFull[0])
        req_enq[0] <= tagged Valid (x);

    method Action deq() if(notEmpty[0]);
        req_deq[0] <= True;
    endmethod

    method t first() if(notEmpty[0]);
        return data[deqP[0]];
    endmethod

endmodule
