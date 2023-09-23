
import FIFO::*;
import FixedPoint::*;
import Vector::*;

import AudioProcessorTypes::*;
import FilterCoefficients::*;
import Multiplier::*;

// The FIR Filter Module Definition
module mkFIRFilter (AudioProcessor);
    FIFO#(Sample) infifo  <- mkFIFO (); //容量为2 没有不空不满信号 不空不满可以同时enq和deq
    FIFO#(Sample) outfifo <- mkFIFO ();
    Vector#(8, Reg#(Sample)) r <- replicateM (mkReg(0));
    Vector#(9, Multiplier)   m <- replicateM (mkMultiplier());

    rule process (True);
        Sample sample = infifo.first();    
        r[0] <= sample;
        infifo.deq();
        for(Integer i = 0; i < 7; i = i + 1) begin
            r[i+1] <= r[i];
        end

        m[0].putOperands(c[0],sample);
        for(Integer i = 0; i < 8; i = i + 1) begin
            m[i+1].putOperands(c[i+1], r[i]);
        end
    endrule

    rule add (True);
        Vector#(9, FixedPoint#(16,16)) res;
        res[0] <- m[0].getResult();   
        for(Integer i = 0; i < 8; i = i + 1) begin
            let x <- m[i+1].getResult(); //动作值方法必须要用<-
            res[i+1] = res[i] + x;
        end
        outfifo.enq (fxptGetInt(res[8]));
    endrule

    method Action putSampleInput(Sample in);
        infifo.enq(in);
    endmethod

    method ActionValue#(Sample) getSampleOutput();
        outfifo.deq();
        return outfifo.first();
    endmethod

endmodule


