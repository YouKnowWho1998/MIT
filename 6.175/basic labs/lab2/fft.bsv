import Vector::*;
import Complex::*;
import Fifo::*;
import FIFOF::*;


interface Fft;
    method Action enq(Vector#(64, ComplexData) in);
    method ActionValue#(Vector#(64, ComplexData)) deq;
endinterface


//=============================================================================================================
//练习2: 
//刚性流水线 使用寄存器
//Bfly4和Permute函数这里不给出 直接调用 当作black box处理
(* synthesize *)
module mkFftInelasticPipeline(Fft);
    FIFOF#(Vector#(64, ComplexData)) inFifo  <- mkFIFOF;
    FIFOF#(Vector#(64, ComplexData)) outFifo <- mkFIFOF; 
    Vector#(3, Vector#(16, Bfly4)) bfly <- replicateM(replicateM(mkBfly4)); 
    Reg#(Maybe#(Vector#(64, ComplexData))) sReg1 <- mkRegU; //例化stage寄存器1
    Reg#(Maybe#(Vector#(64, ComplexData))) sReg2 <- mkRegU; //例化stage寄存器2    

    function Vector#(64, ComplexData) stage_f(StageIdx stage, Vector#(64, ComplexData) in);
        Vector#(64, ComplexData) stage_temp, stage_out;
        for (Fftidx i = 0; i < 16; i = i + 1)  begin
            Fftidx idx = i * 4;
            //以下x, t送去Bly4模块中计算
            Vector#(4, ComplexData) x;
            Vector#(4, ComplexData) t;
            for (Fftidx j = 0; j < 4; j = j + 1) begin
                x[j] = in[idx+j]; //将每4个in数据传递给x向量 送入Bly4模块中计算
                t[j] = getTwiddle(stage, idx+j); 
            end
            let y = bfly[stage][i].bfly4(t, x);
            for(Fftidx j = 0; j < 4; j = j + 1) begin
                stage_temp[idx+j] = y[j];
            end
        end
        stage_out = permute(stage_temp);
        return stage_out;
    endfunction

    rule doFft;
        //第一阶段
        if(inFifo.notEmpty) begin
            sReg1 <= tagged Valid (stage_f(0, inFifo.first));
            inFifo.deq;
        end
        else 
            sReg1 <= tagged Invalid;
        //第二阶段
        case (sReg1) matches
            tagged Invalid: sReg2 <= tagged Invalid;
            tagged Valid.x: sReg2 <= tagged Valid stage_f(1, x);//这里的x代指的是上一阶段的输出：stage_f(0, inFifo.first)
        endcase
        //第三阶段
        if (isValid(sReg2)) begin
            outFifo.enq(stage_f(2, fromMaybe(?, sReg2)));
        end
    endrule

    method Action enq(Vector#(64, ComplexData) in);
        inFifo.enq(in);
    endmethod

    method ActionValue#(Vector#(64, ComplexData)) deq;
        outFifo.deq;
        return outFifo.first;
    endmethod
endmodule 



/*
(* synthesize *)
module mkFftInelasticPipeline(Fft);
    FIFOF#(Vector#(64, ComplexData)) inFifo  <- mkFIFOF;
    FIFOF#(Vector#(64, ComplexData)) outFifo <- mkFIFOF;
    Vector#(3, Vector#(16, Bfly4)) bfly <- replicateM(replicateM(mkBfly4));

    Reg#(Maybe#(Vector#(64, ComplexData))) sReg1 <- mkRegU;
    Reg#(Maybe#(Vector#(64, ComplexData))) sReg2 <- mkRegU;



    rule doFft;

        // At stage 0, doing the first bfly + permute stage.
        if(inFifo.notEmpty) begin
            sReg1 <= tagged Valid (stage_f(0, inFifo.first));
            inFifo.deq;
        end
        else begin
            sReg1 <= tagged Invalid;
        end

        // At stage 1, doing the second bfly + permute
        case (sReg1) matches
            tagged Invalid: sReg2 <= tagged Invalid;
            tagged Valid .x: sReg2 <= tagged Valid stage_f(1, x);
        endcase

        // Last stage
        if (isValid(sReg2)) begin
            outFifo.enq(stage_f(2, fromMaybe(?, sReg2)));
        end

    endrule

    method Action enq(Vector#(64, ComplexData) in);
        inFifo.enq(in);
    endmethod

    method ActionValue#(Vector#(64, ComplexData)) deq;
        outFifo.deq;
        return outFifo.first;
    endmethod
endmodule */

//=============================================================================================================
//练习3：
//弹性流水线 将寄存器换成fifo

(* synthesize *)
module mkFftElasticPipeline(Fft);
    Fifo#(3, Vector#(64, ComplexData)) inFifo <- mkFifo;
    Fifo#(3, Vector#(64, ComplexData)) outFifo <- mkFifo;
    Fifo#(3, Vector#(64, ComplexData)) fifo1 <- mkFifo; //一级fifo
    Fifo#(3, Vector#(64, ComplexData)) fifo2 <- mkFifo; //二级fifo
    Vector#(3, Vector#(16, Bfly4)) bfly <- replicateM(replicateM(mkBfly4));

    function Vector#(64, ComplexData) stage_f(StageIdx stage, Vector#(64, ComplexData) stage_in);
        Vector#(64, ComplexData) stage_temp, stage_out;
        for (FftIdx i = 0; i < 16; i = i + 1)  begin
            FftIdx idx = i * 4;
            Vector#(4, ComplexData) x;
            Vector#(4, ComplexData) twid;
            for (FftIdx j = 0; j < 4; j = j + 1 ) begin
                x[j] = stage_in[idx+j];
                twid[j] = getTwiddle(stage, idx+j);
            end
            let y = bfly[stage][i].bfly4(twid, x);

            for(FftIdx j = 0; j < 4; j = j + 1 ) begin
                stage_temp[idx+j] = y[j];
            end
        end

        stage_out = permute(stage_temp);

        return stage_out;
    endfunction


    rule stage0 if (inFifo.notEmpty && fifo1.notFull);
        fifo1.enq(stage_f(0, inFifo.first));
        inFifo.deq;
    endrule

    rule stage1 if (fifo1.notEmpty && fifo2.notFull);
        fifo2.enq(stage_f(1, fifo1.first));
        fifo1.deq;
    endrule

    rule stage2 if (fifo2.notEmpty && outFifo.notFull);
        outFifo.enq(stage_f(2, fifo2.first));
        fifo2.deq;
    endrule

    method Action enq(Vector#(64, ComplexData) in);
        inFifo.enq(in);
    endmethod

    method ActionValue#(Vector#(64, ComplexData)) deq;
        outFifo.deq;
        return outFifo.first;
    endmethod

endmodule

//=============================================================================================================


