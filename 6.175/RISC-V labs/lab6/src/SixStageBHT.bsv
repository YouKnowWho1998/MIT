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
import Btb::*;
import GetPut::*;
import FPGAMemory::*;
import Scoreboard::*;
import Bht::*;
import FIFO::*;


typedef struct{//取指->解码阶段传入的数据结构体类型
    Addr pc;
    Addr ppc;
    Bool exeEpoch;
    Bool decEpoch;
} Fetch2Decode deriving(Bits, Eq);

typedef struct{//解码->取出寄存器数据阶段传入的数据结构体类型
    Addr pc;
    Addr ppc;
    Bool exeEpoch;
    DecodedInst dInst;
} Decode2Register deriving(Bits, Eq);

typedef struct{//从寄存器数据->处理阶段传入的数据结构体类型
    Addr pc;
    Addr ppc;
    Bool exeEpoch;
    DecodedInst dInst;
    Data rVal1;
    Data rVal2;
    Data csrVal;
} Register2Execute deriving(Bits, Eq);

typedef struct{//处理阶段->数据cache传入的数据结构体类型
    Addr pc;
    Maybe#(ExecInst) eInst;
} Execute2Memory deriving(Bits, Eq);

typedef struct{//内存->回写寄存器数据阶段数据结构体类型
    Addr pc;
    Maybe#(ExecInst) eInst;
} Memory2WriteBack deriving(Bits, Eq);

typedef struct{//执行阶段指令重定向
    Addr pc;
    Addr nextPc;
} ExecuteRedirect deriving(Bits, Eq);

typedef struct{//解码阶段指令重定向
    Addr nextPc;
} DecodeRedirect deriving(Bits, Eq);

//==================================================================================================

(* synthesize *)
module mkProc(Proc)
    Ehr#(2, Addr)      pc   <- mkEhrU;
    RFile              rf   <- mkRFile;
    Scoreboard#(10)    sb   <- mkCFScoreboard;
    FPGAMemory         iMem <- mkFPGAMemory;
    FPGAMemory         dMem <- mkFPGAMemory;
    CsrFile            csrf <- mkCsrFile;
    Btb#(6)            btb  <- mkBtb;
    Bht#(8)            bht  <- mkBht;

    FIFO#(Fetch2Decode)      f2dFifo  <- mkCFFifo;
    FIFO#(Decode2Register)   d2rFifo  <- mkCFFifo;
    FIFO#(Register2Execute)  r2eFifo  <- mkCFFifo;
    FIFO#(Execute2Memory)    e2mFifo  <- mkCFFifo;
    FIFO#(Memory2WriteBack)  m2wbFifo <- mkCFFifo;

    Reg#(Bool) execEpoch <- mkReg(False);
    Reg#(Bool) decEpoch  <- mkReg(False);
    Ehr#(2, Maybe#(ExecuteRedirect)) execRedirect <- mkEhr(Invalid);
    Ehr#(2, Maybe#(DecodeRedirect))  decRedirect  <- mkEhr(Invalid);

    Bool memReady = iMem.init.done() && dMem.init.done();

//--------------------------------------------------------------------------------------------------
    rule doFetch(csrf.started)//取指令阶段
        iMem.req(MemReq{op:?, addr:pc[0], data:?});//向指令缓存发出读请求
        Addr ppc = btb.predPc(pc[0]);
        Fetch2Decode f2d = {
            pc : pc[0],
            ppc : ppc,
            exeEpoch: execEpoch,
            decEpoch: decEpoch
        };
        f2dFifo.enq(f2d);
        pc[0] <= ppc;
        $display("Request instruction: PC = %x, next PC = %x", pc[0], ppc);
    endrule
//----------------------------------------------------------------------------------------------------
    rule doDecode(csrf.started)//指令解码阶段
        let f2d = f2dFifo.first;
        f2dFifo.deq;

        Data inst <- iMem.resp();//指令缓存回应请求 读出指令
        Bool decodeEpochPass1 = (f2d.exeEpoch == execEpoch) ? True : False;
        Bool decodeEpochPass2 = (f2d.decEpoch == decEpoch)  ? True : False;
        //解码阶段检查2个Epoch寄存器的值是否一致，如果不一致不能解码此条指令
        if ((decodeEpochPass1) && (decodeEpochPass2)) begin
            DecodedInst dInst = decode(inst);
            //如果解码指令后发现是分支指令 则需要调用Bht进行跳转预测(检验btb预测的指令是否正确)
            if ((dInst.iType == J) || (dInst.iType == Br)) begin
                let bhtPred = bht.predPc(f2d.pc, f2d.ppc);
                //如果bht预测的跳转结果地址与btb预测的指令地址不符 则btb预测失败 进行指令重定向
                //并将bht预测的跳转地址赋值给预测指令地址
                if (bhtPred != f2d.ppc) begin
                    decRedirect[0] <= tagged valid DecodeRedirect{nextPc : bhtPred};
                    f2d.ppc = bhtPred;
                end
            end
            Decode2Register d2r = {
                pc : f2d.pc,
                ppc : f2d.ppc,
                exeEpoch : f2d.exeEpoch,
                dInst : dInst
            };
            d2rFifo.enq(d2r);
        end
        else begin
            $display("Killing wrong path in Decode");
        end
    endrule
//----------------------------------------------------------------------------------------------------
    rule doRegister(csrf.started)//读取寄存器数据阶段
        let d2r = d2rFifo.first;
        let dInst = d2r.dInst;
        //d2rFifo.deq; 这样写不对 要先查询scoreboard之后才能弹出d2rFifo数据 否则就要等待

        Data   rVal1  = rf.rd1(fromMaybe(?, dInst.src1));
        Data   rVal2  = rf.rd2(fromMaybe(?, dInst.src2));
        Data   csrVal = csrf.rd(fromMaybe(?, dInst.csr));

        //查询scoreboard 看之前指令有无记录要写入的寄存器 排除数据冒险
        let noDataHazard1 = !sb.search1(fromMaybe(?, dInst.src1));
        let noDataHazard2 = !sb.search2(fromMaybe(?, dInst.src2));
        if(noDataHazard1 && noDataHazard2) begin
            d2rFifo.deq;//此时才可弹出数据
            sb.insert(fromMaybe(?, dInst.dst));//向scoreboard输入此次指令要写入的寄存器地址
            Register2Execute r2e = {
                pc : d2r.pc,
                ppc : d2r.ppc,
                epoch : d2r.exeEpoch,
                dInst : dInst,
                rVal1 : rVal1,
                rVal2 : rVal2,
                csrVal : csrVal,
            };
            r2eFifo.enq(r2e);
            $display("Read registers: PC = %x", d2r.pc);
        end
        else begin
            $display("[Stalled] Read registers: PC = %x", d2r.pc);
        end
    endrule
//----------------------------------------------------------------------------------------------------
    rule doExecute(csrf.started);//指令执行阶段
        let r2e = r2eFifo.first;
        r2eFifo.deq;//指令被执行模块接收之后就立刻弹出销毁

        //检测epoch状态是否上级下级一致 如果不一致则销毁此条指令
        //如果分支预测失败，将触发重定向规则销毁此条指令，改变epoch状态，这里将会立刻触发不一致 
        Maybe#(ExecInst) eInst;
        if(r2e.epoch != execEpoch) begin
            eInst = tagged Invalid;
        end
        else begin
            ExecInst e = exec(
                r2e.dInst,
                r2e.rVal1,
                r2e.rVal2,
                r2e.csrVal,
                r2e.pc,
                r2e.ppc
            );
            eInst = tagged Valid e;
            if(eInst.mispredict) begin
                $display("MisPredict!");
                $fflush(stdout);
                Bool jump = ((eInst.iType == J) || (eInst.iType == Jr) || (eInst.iType == Br));
                let realNextPc = jump ? eInst.addr : r2e.pc+4;
                //出现了分支预测失败 则触发重定向规则 改变epoch寄存器值 
                //同时将下一条指令的正确地址发给pc寄存器
                execRedirect[0] <= tagged Valid ExecuteRedirect{
                    pc : r2e.pc;
                    nextPc : realNextPc;
                };
            end
            else begin
                $display("Executed!");
                $fflush(stdout);
            end

            //如果指令执行后发现是条件跳转指令 则调用bht update方法进行更新
            if (e.iType == Br) begin
                bht.update(r2e.pc, e.brTaken);
            end
        end

        Execute2Memory e2m = {
            pc : r2e.pc,
            eInst : eInst,
        };
        e2mFifo.enq(e2m);
    endrule
//----------------------------------------------------------------------------------------------------
    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule canonicalizeRedirect(csrf.started);//重定向规则 分支预测失败时触发
        if (execRedirect[1] matches tagged Valid .r) begin
            pc[1] <= r.nextPc; //将正确的下一条指令地址传给pc寄存器
            execEpoch <= !execEpoch;//同时因为此条指令预测失败改变epoch寄存器值 使此条指令销毁丢弃
            btb.update(r.pc, r.nextPc); //更新分支预测缓冲器
            $display("Fetch: Mispredict, redirected by Execute");
        end
        else if (decRedirect[1] matches tagged Valid .r) begin
            pc[1] <= r.nextPc;
            decEpoch <= !decEpoch;
            $display("Fetch: Mispredict, redirected by Decode");
        end
        execRedirect <= Invalid;
        decRedirect  <= Invalid;
    endrule
//----------------------------------------------------------------------------------------------------
    rule doMemory(csrf.started); //数据内存阶段(根据指令 向内存读写数据)
        let e2m = e2mFifo.first;
        e2mFifo.deq;

        if (isValid(e2m.eInst)) begin
            let x = fromMaybe(?, e2m.eInst);
            if(x.iType == Ld) begin
                dMem.rep(MemReq{op:Ld, addr:x.addr, data:?});
            end
            else if(x.iType == St) begin
                let dummy <- dMem.rep(MemReq{op:St, addr:x.addr, data:x.addr});
            end
        end
        else begin
            $display("Memory stage of poisoned instruction");
            $fflush(stdout);
        end

        Memory2WriteBack m2w = {
            pc : e2m.pc,
            eInst : e2m.eInst,
        };
        m2wbFifo.enq(m2w);
    endrule
//----------------------------------------------------------------------------------------------------
    rule doWriteBack(csrf.started);//回写阶段(回写到寄存器数据)
        let m2w = m2wbFifo.first;
        m2wbFifo.deq;

        if (isValid(m2w.eInst)) begin
            let x = fromMaybe(?, m2w.eInst);
            if(x.iType == Ld) begin
                x.data <- dMem.resp();
            end
            if(isValid(x.dst)) begin
                rd.wr(fromMaybe(?, x.dst), x.data);
            end
            csrf.wr((x.iType == Csrw) ? x.csr : Invalid, x.data);
            $display("WriteBack stage of poisoned instruction");
        end
        else begin
            $display("WriteBack stage of poisoned instruction");
            $fflush(stdout);
        end

        sb.remove;//这条指令已经彻底完成操作 将scoreboard中记录抹掉
    endrule
//----------------------------------------------------------------------------------------------------
    method ActionValue#(CpuToHostData) cpuToHost;
    let ret <- csrf.cpuToHost;
    return ret;
    endmethod


    method Action hostToCpu(Bit#(32) startpc) if(!csrf.started && memReady);
    csrf.start(0);
    $display("STARTING AT PC: %h", startpc);
    $fflush(stdout);
    pcReg[0] <= startpc;
    endmethod

    interface iMemInit=iMem.init;
    interface dMemInit=dMem.init;

endmodule