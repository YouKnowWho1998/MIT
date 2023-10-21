import Types::*;
import ProcTypes::*;
import MemTypes::*;
import RFile::*;
import IMemory::*;
import DMemory::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Vector::*;
import Fifo::*;
import Ehr::*;
import GetPut::*;

typedef struct{ //解码-处理中间级数据结构体变量
    DecodedInst dInst;
    Addr pc;
    Addr ppc; 
} Decode2Execute deriving (Bits, Eq);

//================================================ Processor =============================================================================
(*synthesize*)
module mkProc(Proc);
    Ehr#(2,Addr) pc    <- mkEhrU;
    RFile        rf    <- mkRFile;
    IMemory      iMem  <- mkIMemory;
    DMemory      dMem  <- mkDMemory;
    CsrFile      csrf  <- mkCsrFile;
    Fifo#(2, Decode2Execute) d2e <- mkCFFifo; //例化指令-解码FIFO 容量为2是因为两级流水线 两个rule都是并行执行的

    Bool memReady = iMem.init.done() && dMem.init.done();
//------------------------------------------------------------------------------------------------------------------------------------------
    rule doFetchDecode(csrf.started);
        Decode2Execute dec2exe;
        Data inst = iMem.req(pc[0]);
        let  ppc  = pc[0] + 4;
        dec2exe.dInst = decode(inst);
        dec2exe.pc = pc[0];
        dec2exe.ppc = ppc;

        $display("pc:%h inst:(%h) expanded: ",dec2exe.pc,inst,showInst(inst));
        $fflush(stdout);

        if(dec2exe.dInst.iType == Unsupported) begin
            $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", dec2exe.pc);
            $finish;
        end
        
        //将封装完成的数据(解码完成的指令与pc,ppc)送入FIFO 并开始下一条指令地址的预测
        //同时根据预测的地址获得指令 继续进行下一条指令的解码 此流程持续进行
        d2e.enq(dec2exe);
        pc[0] <= ppc;
    endrule
//------------------------------------------------------------------------------------------------------------------------------------------
    rule doExecute(csrf.started); 
        let exe = d2e.first;
        d2e.deq();

        Data rVal1  = rf.rd1(fromMaybe(?, exe.dInst.src1));
        Data rVal2  = rf.rd2(fromMaybe(?, exe.dInst.src2));
        Data csrVal = csrf.rd(fromMaybe(?, exe.dInst.csr));
        ExecInst eInst = exec(
            exe.dInst,
            rVal1, 
            rVal2,
            exe.pc, 
            exe.ppc,
            csrVal
        );

        if(eInst.iType == Ld) begin
            eInst.data <- dMem.req(MemReq{op:Ld, addr:eInst.addr, data:?});    
        end 
        else if(eInst.iType == St) begin
            let dummy <- dMem.req(MemReq{op:St, addr:eInst.addr, data:eInst.data});
        end

        if(isValid(eInst.dst)) begin
            rf.wr(fromMaybe(?, eInst.dst), eInst.data);
        end

        if(eInst.mispredict) begin
            $display("Mispredict!");
            $fflush(stdout);
            d2e.clear();
            if(eInst.brTaken) begin
                pc[1] <= eInst.addr;//EHR寄存器[1]端口优先级更高 如果预测错误 
            end                     //将处理后的正确指令地址赋值给pc寄存器
        end

        csrf.wr((eInst.iType == Csrw) ? eInst.csr : Invalid, eInst.data);        
    endrule
//------------------------------------------------------------------------------------------------------------------------------------------
    method ActionValue#(CpuToHostData) cpuToHost;
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod
//------------------------------------------------------------------------------------------------------------------------------------------
    method Action hostToCpu(Bit#(32) startpc) if(!csrf.started && memReady);
        csrf.start(0);
        $display("STARTING AT PC: %h", startpc);
	    $fflush(stdout);
        pc[0] <= startpc;
    endmethod
//------------------------------------------------------------------------------------------------------------------------------------------
    interface iMemInit = iMem.init;
    interface dMemInit = dMem.init;
endmodule
