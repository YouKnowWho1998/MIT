import Types::*;
import ProcTypes::*;
import MemTypes::*;
import RFile::*;
import Decode::*;
import Exec::*;
import CsrFile::*;
import Fifo::*;
import Ehr::*;
import GetPut::*;
import ICache::*;
import DCache::*;
import DCacheStQ::*;
import DCacheLHUSM::*;
import MemReqIDGen::*;
import CacheTypes::*;
import MemUtil::*;
import Vector::*;
import FShow::*;
import MessageFifo::*;
import RefTypes::*;

typedef enum {//定义处理器阶段状态机
	Fetch,
	Execute,
	Commit
} Stage deriving(Bits, Eq, FShow);

//================================================ ThreeCycle ===========================================================================

module mkCore#(CoreID id)(
	WideMem iMem,    //指令缓存
	RefDMem refDMem, //用于Debug
	Core ifc         //接口
);

    Reg#(Addr)          pc  <- mkRegU;
    CsrFile           csrf  <- mkCsrFile(id);
    RFile               rf  <- mkRFile;
	Reg#(ExecInst) eInstReg <- mkRegU; //执行阶段寄存器
	Reg#(Stage)       stage <- mkReg(Fetch);//阶段状态机
	ICache           iCache <- mkICache(iMem); //指令缓存

    //
	MemReqIDGen memReqIDGen <- mkMemReqIDGen;

    //与PPP模块交互
	MessageFifo#(2) toParentQ   <- mkMessageFifo;
	MessageFifo#(2) fromParentQ <- mkMessageFifo;

    //数据缓存
    DCache dCache <- mkDCacheLHUSM(
        id,
        toMessageGet(fromParentQ),
        toMessagePut(toParentQ),
        refDMem
    );

    // DCache dCache <- mkDCacheStQ(
    //     id,
    //     toMessageGet(fromParentQ),
    //     toMessagePut(toParentQ),
    //     refDMem
    // );

    // DCache dCache <- mkDCache(
    //             id,
    //             toMessageGet(fromParentQ),
    //             toMessagePut(toParentQ),
    //             refDMem
    //         );

//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule doFetch(csrf.started && stage == Fetch);
        iCache.req(pc);
        stage <= Execute;
        $display("%0t: core %d: Fetch: PC = %h", $time, id, pc);
    endrule
//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule doExecute(csrf.started && stage == Execute);
        let inst <- iCache.resp;
        //解码指令
        let dInst = decode(inst);
        let rVal1 = rf.rd1(validValue(dInst.src1));
        let rVal2 = rf.rd2(validValue(dInst.src2));
        let csrVal = csrf.rd(validValue(dInst.csr));
        //执行指令
        let eInst = exec(dInst, rVal1, rVal2, pc, ?, csrVal);

        $display("%0t: core %d: Exe: inst (%h) expanded: ", $time, id, inst, showInst(inst));
        //如果是不支持指令 则报错
        if(eInst.iType == Unsupported) begin
            $fwrite(stderr, "ERROR: Executing unsupported instruction. Exiting\n");
            $finish;
        end

        //如果是Load指令则从数据缓存加载数据
        if(eInst.iType == Ld) begin
            let rid <- memReqIDGen.getID;
            let r = MemReq{op: Ld, addr: eInst.addr, data: ?, rid: rid};
            dCache.req(r);
            $display("Exe: issue mem req ", fshow(r), "\n");
        end
        //如果是Store指令则向数据缓存存入数据
        else if(eInst.iType == St) begin
            let rid <- memReqIDGen.getID;
            let r = MemReq{op: St, addr: eInst.addr, data: eInst.data, rid: rid};
            dCache.req(r);
            $display("Exe: issue mem req ", fshow(r), "\n");
        end
        //如果是Lr指令 则从内存地址中加载数据到RD寄存器并设置保留标记 
        else if(eInst.iType == Lr) begin
            let rid <- memReqIDGen.getID;
            let r = MemReq{op: Lr, addr: eInst.addr, data: ?, rid: rid};
            dCache.req(r);
            $display("Exe: issue mem req ", fshow(r), "\n");
        end
        //如果是Sc指令 同时有保留标记则加载数据到内存地址里
        else if(eInst.iType == Sc) begin
            let rid <- memReqIDGen.getID;
            let r = MemReq{op: Sc, addr: eInst.addr, data: eInst.data, rid: rid};
            dCache.req(r);
            $display("Exe: issue mem req ", fshow(r), "\n");
        end
        //Fence指令用于同步所有内存操作。它将保证在它之前的所有内存操作都完成,而在它之后的内存操作要在它之后执行
        else if(eInst.iType == Fence) begin
            let rid <- memReqIDGen.getID;
            let r = MemReq{op: Fence, addr: ?, data: ?, rid: rid};
            dCache.req(r);
            $display("Exe: issue mem req ", fshow(r), "\n");
        end
        else begin
            $display("Exe: no mem op");
        end
        // save eInst & change stage
        eInstReg <= eInst;
        stage    <= Commit;
    endrule
//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule doCommit(csrf.started && stage == Commit);
        ExecInst eInst = eInstReg;
        //如果是Ld/Lr/Sc指令 获得数据缓存返回值
        if(eInst.iType == Ld || eInst.iType == Lr || eInst.iType == Sc) begin
            eInst.data <- dCache.resp;
        end
        //WriteBack阶段
        if(isValid(eInst.dst)) begin
            rf.wr(fromMaybe(?, eInst.dst), eInst.data);
        end
        csrf.wr(eInst.iType == Csrw ? eInst.csr : Invalid, eInst.data);
        $display("%0t: core %d: Commit, eInst.data = %h", $time, id, eInst.data);
        
        pc <= eInst.brTaken ? eInst.addr : pc+4;
        stage <= Fetch;
    endrule
//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    interface MessageGet toParent = toMessageGet(toParentQ);
    interface MessagePut fromParent = toMessagePut(fromParentQ);

    method ActionValue#(CpuToHostData) cpuToHost if(csrf.started);
        let ret <- csrf.cpuToHost;
        return ret;
    endmethod
//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    method Bool cpuToHostValid = csrf.cpuToHostValid;

    method Action hostToCpu(Bit#(32) startpc) if (!csrf.started);
        csrf.start;
        pc <= startpc;
    endmethod
//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
endmodule