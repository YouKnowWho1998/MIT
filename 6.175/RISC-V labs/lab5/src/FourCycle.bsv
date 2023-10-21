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

typedef enum{ //定义状态机寄存器状态枚举变量类型
    Fetch, 
    Decode,
    Execute,
    WriteBack
} State deriving(Bits, Eq, FShow);

typedef struct{ //定义解码—执行变量类型
    DecodedInst dInst;
    Data rd1;
    Data rd2;
    Data csrVal;
} Decode2Exec deriving(Bits,Eq);

//================================================= Processor =====================================================================================
module mkProc(Proc);
    Reg#(Addr)    pc     <- mkRegU;
    RFile         rf     <- mkRFile;
    DelayedMemory mem    <- mkDelayedMemory;//例化延迟内存模块
    MemInitIfc dummyInit <- mkDummyMemInit; //只用了一个内存模块 这个用不到
    CsrFile      csrf    <- mkCsrFile;
    
    //例化中间寄存器模块
    Reg#(State)        state <- mkRegU;
    Reg#(Decode2Exec)  d2e   <- mkRegU;
    Reg#(ExecInst)     e2w   <- mkRegU;

    Bool memReady = mem.init.done && dummyInit.done;
//---------------------------------------------------- 指令预取 ---------------------------------------------------------------------------------------------
    rule doFetch(csrf.started && state==Fetch);
        mem.req(MemReq{op:?, addr:pc, data:?});
        state <= Decode;
    endrule
//---------------------------------------------------- 指令解码 ----------------------------------------------------------------------------------------------------
    rule doDecode(csrf.started && state==Decode);
        Data        inst <- mem.resp;
        DecodedInst dInst = decode(inst);

        //Decode2Exec类型中间寄存器变量
        Decode2Exec x;
        x.dInst  = dInst;
        x.rd1    = rf.rd1(fromMaybe(?, dInst.src1));
        x.rd2    = rf.rd2(fromMaybe(?, dInst.src2));
        x.csrVal = csrf.rd(fromMaybe(?, dInst.csr));
        //解码-处理中间寄存器与状态机寄存器赋值
        d2e <= x;
        state <= Execute;
    endrule
//------------------------------------------------------- 指令处理 -----------------------------------------------------------------------------------------------------------
    rule doExecute(csrf.started && state==Execute);
        ExecInst eInst = exec(dInst, x.rd1, x.rd2, pc, ? ,x.csrVal);
        $display("pc:%h inst:(%h) expanded: ",pc,inst,showInst(inst));
        $fflush(stdout);
        
        if(eInst.iType == Unsupported) begin
            $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", pc);
            $finish;
        end

        if(eInst.iType == Ld) begin
            mem.req(MemReq{op:Ld, addr:eInst.addr, data:?});//别忘了内存是有延迟的 
        end else if(eInst.iType == St) begin                //读取结果在下个周期才能准备就绪
            let dummy = mem.req(MemReq{op:St, addr:eInst.addr, data:eInst.data});
        end

        //处理-回写寄存器与状态机寄存器赋值
        e2w   <= eInst;
        state <= WriteBack;
    endrule
//-------------------------------------------------------- 指令回写 -------------------------------------------------------------------------------------------------------------------------
    rule doWriteBack(csrf.started && state==WriteBack);
        //dst是Maybe型index地址 如果是Invalid则不允许更新寄存器文件
        if(isValid(e2w.dst)) begin 
            if(e2w.iType == Ld) begin
                Data loaddata = mem.resp;
                rf.wr(fromMaybe(?, e2w.dst), loaddata);
                end 
            else begin
                rf.wr(fromMaybe(?, e2w.dst), e2w.data);
            end
        end
        else begin
            if(e2w.iType == Ld) begin
                Data dummy = mem.resp;
            end
        end
    

        pc <= e2w.brTaken ? e2w.addr : pc + 4;
        csrf.wr(e2w.iType == Csrw ? e2w.csr : Invalid, e2w.data);
        state <= Fetch;
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
        pc <= startpc;
        state <= Fetch;
    endmethod
//------------------------------------------------------------------------------------------------------------------------------------------
    interface iMemInit = mem.init;
    interface dMemInit = dummyInit;

endmodule









































