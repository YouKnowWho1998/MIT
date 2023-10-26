import Types::*;
import ProcTypes::*;
import MemTypes::*;
import RFile::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Fifo::*;
import Ehr::*;
import Btb::*;
import Scoreboard::*;
import Bht::*;
import GetPut::*;
import ClientServer::*;
import Memory::*;
import ICache::*;
import DCache::*;
import CacheTypes::*;
import WideMemInit::*;
import MemUtil::*;
import Vector::*;
import FShow::*;


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
    Bool decEpoch;
    DecodedInst dInst;
} Decode2Register deriving(Bits, Eq);

typedef struct{//从寄存器数据->处理阶段传入的数据结构体类型
    Addr pc;
    Addr ppc;
    Bool exeEpoch;    
    Bool decEpoch;
    DecodedInst dInst;
    Data rVal1;
    Data rVal2;
    Data csrVal;
} Register2Execute deriving(Bits, Eq);

typedef struct{//处理阶段->回写阶段数据结构体类型
    Addr pc;
    Addr ppc;
    Maybe#(ExecInst) eInst;
} Execute2WriteBack deriving(Bits, Eq);

typedef struct{//指令重定向
    Addr pc;
    Addr nextPc;
} Redirect deriving(Bits, Eq);


//========================================= PROCESSOR ==========================================================

(* synthesize *)
module mkProc#(Fifo#(2, DDR3_Req) ddr3ReqFifo, Fifo#(2, DDR3_Resp) ddr3RespFifo) (Proc);
    Ehr#(2, Addr)      pc   <- mkEhrU;
    RFile              rf   <- mkRFile;
    Scoreboard#(6)     sb   <- mkCFScoreboard;
    CsrFile            csrf <- mkCsrFile;
    Btb#(6)            btb  <- mkBtb;
    Bht#(8)            bht  <- mkBht;

    Fifo#(2, Fetch2Decode)      f2dFifo  <- mkCFFifo;
    Fifo#(2, Decode2Register)   d2rFifo  <- mkCFFifo;
    Fifo#(2, Register2Execute)  r2eFifo  <- mkCFFifo;
    Fifo#(2, Execute2WriteBack) e2mFifo  <- mkCFFifo;
    Fifo#(2, Execute2WriteBack) m2wbFifo <- mkCFFifo;

    Reg#(Bool) execEpoch <- mkReg(False);
    Reg#(Bool) decEpoch  <- mkReg(False);
    Ehr#(2, Maybe#(ExecuteRedirect)) execRedirect <- mkEhr(Invalid);
    Ehr#(2, Maybe#(DecodeRedirect))  decRedirect  <- mkEhr(Invalid);

    Bool memReady = True;

    // interface WideMem;
    //     method Action req(WideMemReq r);
    //     method ActionValue#(CacheLine) resp;
    // endinterface

    //真实的DDR3接口是ddr3ReqFifo和ddr3RespFifo,此模块将其例化为更友好的WideMem类型接口
    WideMem wideMem <- mkWideMemFromDDR3(ddr3ReqFifo, ddr3RespFifo);

    //调用此模块将单个DDR3内存接口(WideMem)拆分成两个，对应指令Cache和数据Cache部分
    Vector#(2, WideMem) splitMem <- mkSplitWideMem(memReady && csrf.started, wideMem);

    //将内存接口类型(WideMem)转化成Cache接口类型 对应指令Cache和数据Cache
    Cache iMem <- mkICache(splitMem[0]);
    Cache dMem <- mkDCacheLHUSM(splitMem[1]);
    // Cache dMem <- mkDCacheStQ(splitMem[1]);
    // Cache dMem <- mkDCache(splitMem[1]);
//-----------------------------------------------------------------------------------------------------------------
    //为初始化时排空内存接收FIFO
    rule drainMemResponses(!csrf.started);
        $display("drain!");
        ddr3RespFifo.deq;
    endrule
//----------------------------------------取指令阶段--------------------------------------------------------------
    rule doFetch(csrf.started);
        iMem.req(MemReq{op:?, addr:pc[0], data:?});//向指令缓存发出读请求
        Addr ppc = btb.predPc(pc[0]);
        Fetch2Decode f2d = Fetch2Decode{
            pc : pc[0],
            ppc : ppc,
            exeEpoch: execEpoch,
            decEpoch: decEpoch
        };
        f2dFifo.enq(f2d);
        pc[0] <= ppc;
        $display("Request instruction: PC = %x, next PC = %x", pc[0], ppc);
    endrule
//----------------------------------------指令解码阶段------------------------------------------------------------
    rule doDecode(csrf.started);
        let f2d = f2dFifo.first;
        f2dFifo.deq;
        Data inst <- iMem.resp();//指令缓存回应请求 读出指令
        Bool decodeEpochPass1 = (f2d.exeEpoch == execEpoch) ? True : False;
        Bool decodeEpochPass2 = (f2d.decEpoch == decEpoch)  ? True : False;

        //解码阶段检查2个Epoch寄存器的值是否一致，如果不一致不能解码此条指令
        if ((decodeEpochPass1) && (decodeEpochPass2)) begin
            DecodedInst dInst = decode(inst);
            //如果解码指令是条件跳转或者无条件跳转类型
            if (dInst.iType == Br || dInst.iType == J) begin
                //如果预测值正确且是无条件跳转类型,则直接加上解码后的imm立即数获得跳转地址
                //否则就是pc值加4
                if (bht.predict(f2d.pc) && dInst.iType == J) begin
                    Addr bht_ppc = f2d.pc + fromMaybe(?, dInst.imm);
                end
                else begin
                    Addr bht_ppc = f2d.pc + 4;
                end

                //如果bht_ppc与f2d.不一样 则指令需要重定向 并将bht_ppc值设定为准确的预测地址
                if (bht_ppc != f2d.ppc) begin
                    DecodeRedirect[0] <= tagged Valid Redirect{
                        pc : f2d.pc,
                        nextPc : bht_ppc
                    };
                    f2d.ppc = bht_ppc;
                end
            end
            Decode2Register d2r = Decode2Register{
                pc : f2d.pc,
                ppc : f2d.ppc,
                exeEpoch : f2d.exeEpoch,
                decEpoch : f2d.decEpoch,
                dInst : dInst
            };
            d2rFifo.enq(d2r);
        end
        else begin
            $display("Killing wrong path in Decode");
        end
    endrule
//---------------------------------------读取寄存器数据阶段-------------------------------------------------------------
    rule doRegister(csrf.started);
        let d2r = d2rFifo.first;
        let dInst = d2r.dInst;
        //d2rFifo.deq; 这样写不对 要先查询scoreboard之后才能弹出d2rFifo数据 否则就要等待

        //查询scoreboard 看之前指令有无记录要写入的寄存器 排除数据冒险
        let noDataHazard1 = !sb.search1(dInst.src1);
        let noDataHazard2 = !sb.search2(dInst.src2);
        if(noDataHazard1 && noDataHazard2) begin
            d2rFifo.deq;//此时才可弹出数据
            Data  rVal1  = rf.rd1(fromMaybe(?, dInst.src1));
            Data  rVal2  = rf.rd2(fromMaybe(?, dInst.src2));
            Data  csrVal = csrf.rd(fromMaybe(?, dInst.csr));
            Register2Execute r2e = Register2Execute{
                pc : d2r.pc,
                ppc : d2r.ppc,
                exeEpoch : d2r.exeEpoch,
                dInst : dInst,
                rVal1 : rVal1,
                rVal2 : rVal2,
                csrVal : csrVal
            };
            sb.insert(dInst.dst);//向scoreboard输入此次指令要写入的寄存器地址
            r2eFifo.enq(r2e);
            $display("Read registers: PC = %x", d2r.pc);
        end
        else begin
            $display("[Stalled] Read registers: PC = %x", d2r.pc);
        end
    endrule
//-------------------------------------------指令执行阶段---------------------------------------------------------
    rule doExecute(csrf.started);
        let r2e = r2eFifo.first;
        r2eFifo.deq;//指令被执行模块接收之后就立刻弹出
        Maybe#(ExecInst) eInst;

        //检测epoch状态是否上级下级一致 如果不一致则销毁此条指令
        //如果分支预测失败，将触发重定向规则销毁此条指令，改变epoch状态，这里将会立刻触发
        if(r2e.exeEpoch != execEpoch) begin
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

            //出现了分支预测失败 则触发重定向规则 改变epoch值 设定为wrong path 
            //同时将下一条指令的正确地址发给pc寄存器            
            if(e.mispredict) begin
                $display("MisPredict!");
                $fflush(stdout);
                execRedirect[0] <= tagged Valid Redirect{
                    pc : r2e.pc,
                    nextPc : e.addr
                };
            end

            //执行阶段完成后 如果是条件跳转指令 则调用update方法更新Bht
            if (e.iType == Br) begin
                bht.train(r2e.pc, e.brTaken);
            end
        end

        Execute2Memory e2m = Execute2WriteBack{
            pc : r2e.pc,
            ppc : r2e.ppc,
            eInst : eInst
        };
        e2mFifo.enq(e2m);
    endrule
//------------------------------------------重定向规则---------------------------------------------------------
    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule canonicalizeRedirect(csrf.started);//分支预测失败时触发
        if (execRedirect[1] matches tagged Valid .r) begin
            pc[1] <= r.nextPc; //将正确的下一条指令地址传给pc寄存器
            execEpoch <= !execEpoch;//同时改变epoch值 使此条错误指令销毁 同时使取指阶段取到正确的PC值
            btb.update(r.pc, r.nextPc); //更新btb
            $display("Fetch: Mispredict, redirected by Execute");
        end
        else if (decRedirect[1] matches tagged Valid .r) begin
            pc[1] <= r.nextPc;
            decEpoch <= !decEpoch;
            $display("Fetch: Mispredict, redirected by Decode");
        end
        execRedirect[1] <= Invalid;
        decRedirect[1]  <= Invalid;
    endrule
//----------------------------------数据内存阶段(根据指令, 向内存读写数据)--------------------------------------------------------------
    rule doMemory(csrf.started); //
        let e2m = e2mFifo.first;
        e2mFifo.deq;

        if (isValid(e2m.eInst)) begin
            let x = fromMaybe(?, e2m.eInst);
            if(x.iType == Ld) begin
                dMem.req(MemReq{op:Ld, addr:x.addr, data:?});
            end
            else if(x.iType == St) begin
                dMem.req(MemReq{op:St, addr:x.addr, data:x.data});
            end
        end
        else begin
            $display("Memory stage of poisoned instruction");
            $fflush(stdout);
        end

        m2wbFifo.enq(e2m);
    endrule
//---------------------------------------回写阶段(回写到寄存器数据)-------------------------------------------------------------
    rule doWriteBack(csrf.started);
        let m2w = m2wbFifo.first;
        m2wbFifo.deq;

        if (isValid(m2w.eInst)) begin
            let x = fromMaybe(?, m2w.eInst);

            //如果是load指令 从数据缓存中读取数据
            if(x.iType == Ld) begin
                x.data <- dMem.resp();
            end

            //如果是不支持的指令
            if(x.iType == Unsupported) begin
                $fwrite(stderr, "ERROR: Executing unsupported instruction at pc: %x. Exiting\n", dMsg.pc);
                $finish;
            end

            if(isValid(x.dst)) begin
                rf.wr(fromMaybe(?, x.dst), x.data);
            end

            csrf.wr((x.iType == Csrw) ? x.csr : Invalid, x.data);
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
//----------------------------------------------------------------------------------------------------
    method Action hostToCpu(Bit#(32) startpc) if(!csrf.started && memReady);
    csrf.start(0);
    $display("STARTING AT PC: %h", startpc);
    $fflush(stdout);
    pc[0] <= startpc;
    endmethod
//----------------------------------------------------------------------------------------------------
endmodule