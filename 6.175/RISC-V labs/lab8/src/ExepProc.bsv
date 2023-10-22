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

//================================================= Processor =========================================================================================

(*synthesize*)
module mkProc(Proc);
    Reg#(Addr)  pc   <- mkRegU;
    RFile       rf   <- mkRFile;
    IMemory     iMem <- mkIMemory;
    DMemory     dMem <- mkDMemory;
    CsrFile     csrf <- mkCsrFile;

    Bool memReady = iMem.init.done() && dMem.init.done();
//--------------------------------------------------------------------------------------------------------------------------
    rule doProc(csrf.started);
        //mstatus[2:1]是00则是用户模式 11则是机器模式
        //只有在机器模式才允许使用eret和csrrw指令，否则decode模块会将此条指令的iType设为NoPermisson
        Bool  userModeOn   = (csrf.getMstatus[2:1] == 2'b00) ? True : False;
        Data        inst   = iMem.req(pc);
        DecodedInst dInst  = decode(inst, userModeOn);
        Data        rVal1  = rf.rd1(fromMaybe(?,dInst.src1));
        Data        rVal2  = rf.rd2(fromMaybe(?,dInst.src2));
        Data        csrVal = csrf.rd(fromMaybe(?,dInst.csr));
        ExecInst    eInst  = exec(
            dInst,
            rVal1,
            rVal2,
            pc,
            ?,
            csrVal
            );
        $display("pc:%h inst:(%h) expanded: ",pc,inst,showInst(inst));
        $fflush(stdout);

        if(eInst.iType == Unsupported) begin
            $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", pc);
            $finish;
        end

        if(eInst.iType == Ld) begin
            eInst.data <- dMem.req(MemReq{op:Ld, addr:eInst.addr, data:?});    
        end 
        else if(eInst.iType == St) begin
            let dummy <- dMem.req(MemReq{op:St, addr:eInst.addr, data:eInst.data});
        end

        // mstatus寄存器的低12位是一个4×3bit的堆栈,如mstatus[2:0]是栈顶, mstatus[0]是IE位
        // IE位为1是中断(interrupt)，mstatus[2:1]是模式标识位, 用户模式为00，机器模式为11
        // 当发生异常(exception)时，堆栈将左移3位，新标识位和IE位现在存储到mstatus[2:0]中
        // 当使用eret指令从异常返回时，堆栈将右移3位，mstatus[2:0]将包含其原始值，并且mstatus[11:9]被分配给[用户模式,中断使能]
        // 异常原因是不支持的指令
        if(eInst.iType == NoPermission) begin
            $fwrite(stderr, "ERROR: Executing NoPermission instruction. Exiting\n");
            $finish;
        end 
        else if(eInst.iType == Unsupported) begin
            $display("Unsupported instruction. Enter Trap");
            Data status = csrf.getMstatus << 3;
            status[2:0] = 3'b110;//新的堆栈值
            //把异常指令的PC值赋给mepc寄存器，异常原因(32'h02)赋给mcause寄存器
            //现在状态赋值给mstatus寄存器
            csrf.startExcep(pc, 32'h02, status);
            //将mtvec的值赋值给PC，mtvec寄存器存储异常处理程序的起始地址
            pc <= csrf.getMtvec;
        end
        //异常原因是系统调用指令
        else if(eInst.iType == ECall) begin
            $display("System call. Enter Trap");
            Data status = csrf.getMstatus << 3;
            status[2:0] = 3'b110;
            csrf.startExcep(pc, 32'h08, status);
            pc <= csrf.getMtvec;
        end 
        //eret指令用于从异常处理中返回, 将mstatus右移3位, mstatus[2:0]是其原始值
        //并且status[11:9]被赋值[用户模式,中断使能], 3'b001
        else if(eInst.iType == ERet) begin
            Data status = csrf.getMstatus >> 3;
            status[11:9] = 3'b001;
            csrf.eret(status);
            pc <= csrf.getMepc;//eret指令将PC设置为mepc寄存器的值
        end
        else begin
            if(isValid(eInst.dst)) begin
                rf.wr(fromMaybe(?,eInst.dst),eInst.data);
            end
            pc <= eInst.brTaken ? eInst.addr : pc+4;
            csrf.wr(eInst.iType == Csrrw ? eInst.csr : Invalid, eInst.csrData);
        end
    endrule
//--------------------------------------------------------------------------------------------------------------------------
    method ActionValue#(CpuToHostData) cpuToHost;
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod
//--------------------------------------------------------------------------------------------------------------------------
    method Action hostToCpu(Bit#(32) startpc) if(!csrf.started && memReady);
        csrf.start(0);
        $display("STARTING AT PC: %h", startpc);
	    $fflush(stdout);
        pc <= startpc;
    endmethod
//--------------------------------------------------------------------------------------------------------------------------
    interface iMemInit = iMem.init;
    interface dMemInit = dMem.init;
endmodule
//=======================================================================================================================================