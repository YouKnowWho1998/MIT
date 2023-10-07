import FIFO::*;

//=============================================================================================================
//练习1：


interface Fifo#(numeric type n, type td);
    method Action enq(td x);
    method Action deq;
    method td first;
    method Bool notEmpty;
    method Bool notFull;
endinterface


module mkFifo3#(Fifo#(3, td))
    provisos (Bits#(td));
    Reg#(td) da <- mkRegU();
    Reg#(td) db <- mkRegU();    
    Reg#(td) dc <- mkRegU();    
    Reg#(Bool) va <- mkReg(False);
    Reg#(Bool) vb <- mkReg(False);
    Reg#(Bool) vc <- mkReg(False);

    method Action enq(td x) if(!va);
        if(!vc) begin
            dc <= x;
            vc <= True; end
        else if(!vb) begin
            db <= x;
            vb <= True; end    
        else begin
            da <= x;
            va <= True; end
    endmethod

    method Action deq() if(vc);
        if(vb) begin
            dc <= db;
            db <= da;
            va <= False; end
        else 
            vc <= False; 
    endmethod
    
    method td first if(vc);
        return dc;
    endmethod

    method Bool notEmpty if(vc);
        return True;
    endmethod

    method Bool notFull if(!va);
        return True;
    endmethod    

endmodule



/*
module mkFifo(Fifo#(3,td)) 
    provisos (Bits#(td,sz1)); //td必须派生自Bits# 同时获得它的位宽sz1
    Reg#(Maybe#(td)) d[3];
    for(Integer i = 0; i < 3; i = i + 1) begin
        d[i] <- mkReg(tagged Invalid); end


 // Enq if there's at least one spot open... so, dc is invalid.
    method Action enq(td x) if (!isValid (d[2]));
        if (!isValid (d[0])) begin
            d[0] <= tagged Valid x; end
        else if(!isValid (d[1])) begin
            d[1] <= tagged Valid x; end
        else begin
            d[2] <= tagged Valid x; end
    endmethod


    // Deq if there's a valid d[0]ta at d[0]
    method Action deq() if (isValid (d[0]));
        if (isValid (d[1])) begin
            d[0] <= d[1];
            d[1] <= d[2];
            d[2] <= tagged Invalid;
        end
        else begin
            d[0] <= tagged Invalid;
        end
    endmethod

    // First if there's a valid data at d[0]
    method t first() if (isValid (d[0]));
        return fromMaybe (?, d[0]);
    endmethod

    // Check if fifo's empty
    method Bool notEmpty();
        return isValid(d[0]);
    endmethod

    method Bool notFull();
        return !isValid(d[2]);
    endmethod

endmodule


