import CacheTypes::*;
import Vector::*;
import FShow::*;
import MemTypes::*;
import Types::*;
import ProcTypes::*;
import Fifo::*;
import Ehr::*;
import RefTypes::*;


// "M", "S", "I"这3个字母代表了一个Cache Line可能的三种状态，分别是Modified, Shared和Invalid。当多个CPU核心从内存读取了数据到自己的cache line，此时这些CPU中的这些cache line中的数据都是一样的                                                                                                *  
// 和内存对应位置的数据也是一样的，cache line都处于shared状态。接下来CPU2将自己cache line的数据更改为13，                                                                                                      
// CPU2的这条cache line就变为modified状态（S-->M），其他CPU的cache line就变为invalid状态（S-->I）。然后如果CPU1试图读取这条cache line中的数据，由于是invalid状态，于是将触发cache miss(细分的话叫read miss)，
// 那么CPU2将会把自己cache line的数据写回(writeback)到内存，供CPU1从内存读取，之后CPU1和CPU2的cache line都将回到shared状态（I-->S, M-->S）。                                                                  
// 如果CPU1不是读取，而是写入这条cache line，那么也将触发cache miss(细分是write miss)，CPU1的cache line将变为modified状态（I-->M），而CPU2的cache line将变为invalid状态（M-->I）。                            
// 无论什么时刻，在某个内存位置和它对应的所有cache line中，至多有一个CPU的cache line可以处于modified状态，代表着最新的数据。其他CPU中cache line中的数据过时没关系，把状态标记为失效就可以了。                
// 各个CPU中，对应内存同一位置的cache line，可以同时处于shared状态，可以一个处于modified状态，其他处于invalid状态，还可以一部分处于shared状态，另一部分处于invalid状态。                                     


// lr指令是从内存地址rs1中加载内容到rd寄存器。然后在rs1对应地址上设置保留标记(reservation set)  
//                                                                                                
// sc指令是在把rs2值写到rs1地址之前，会先判断rs1内存地址是否有设置保留标记，如果设置了，则把rs2 
// 值正常写入到rs1内存地址里，并把rd寄存器设置成 0，表示保存成功。如果rs1内存地址没有设置保留标 
// 记，则不保存，并把rd寄存器设置成1表示保存失败。不管成功还是失败，sc指令都会把当前hart保留的  
// 所有保留标记全部清除。                                                                             

typedef enum {//Cache状态机变量
    Ready, 
    StartMiss, 
    SendFillReq, 
    WaitFillResp, 
    Resp
} CacheStatus deriving(Eq, Bits);


//============================================= DCache =======================================================================================

// interface DCache;
//   method Action req(MemReq r);
//   method ActionValue#(MemResp) resp;
// endinterface

module mkDCacheStQ#(CoreID id)(
    MessageGet fromMem,//Router -> Cache
    MessagePut toMem,//Cache -> Router
    RefDMem    refDMem,//用于调试
    DCache     ifc//接口
); 

    Fifo#(2, Data)	    hitQ 	 <- mkBypassFifo;//是否命中状态
    Fifo#(1, MemReq)    reqQ     <- mkBypassFifo;//来自处理器的所有请求将首先进入reqQ队列
    Reg#(MemReq)        missReq  <- mkRegU;//未命中请求      
    Reg#(CacheStatus)   state    <- mkReg(Ready);//Cache状态机
    StQ#(StQSize)       stq      <- mkStQ; //存储队列
    Reg#(Maybe#(CacheLineAddr)) lineAddr <- mkReg(Invalid); //该寄存器记录lr.w保留的缓存行地址（如果该寄存器有效）

    //Data部分阵列
    Vector#(CacheRows, Reg#(CacheLine)) dataArray <- replicateM(mkRegU);

    //Tag部分阵列
    Vector#(CacheRows, Reg#(CacheTag))  tagArray  <- replicateM(mkRegU);

    //MSI标识位部分阵列
    Vector#(CacheRows, Reg#(MSI))  privArray <- replicateM(mkReg(I));

//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule doLoad(state == Ready && (reqQ.first.op == Ld || (reqQ.first.op == Lr && !stq.notEmpty)));
        MemReq r = reqQ.first;
        reqQ.deq;

        CacheWordSelect sel = getWordSelect(r.addr);
        CacheIndex idx = getIndex(r.addr);
        CacheTag tag = getTag(r.addr);
    // 当处理Sc请求时，我们首先检查linkAddr中的保留地址是否与Sc请求访问的地址匹配。如果  
    // linkAddr无效或地址不匹配，我们直接向核心响应值1，指示存储条件操作失败。否则，我们 
    // 将继续将其作为St请求进行处理。                                                    

        let x = stq.search(r.addr);
        let hit = False;
        if (isValid(x)) begin
            hitQ.enq(fromMaybe(?, x));
            refDMem.commit(r, Invalid, x);
            hit = True;
        end
        else begin
            if (tagArray[idx] == tag && privArray[idx] > I) begin
                hitQ.enq(dataArray[idx][sel]);
                refDMem.commit(r, Valid(dataArray[idx]), Valid(dataArray[idx][sel]));
                hit = True;
            end
            else begin
                missReq <= r;
                state <= StartMiss;
            end
        end

        if (hit && r.op == Lr) begin
            linkAddr <= tagged Valid getLineAddr(r.addr);
        end
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule doStore(reqQ.first.op == St);
        MemReq r = reqQ.first;
        reqQ.deq;
        stq.enq(r);
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule doSc (state == Ready && reqQ.first.op == Sc && !stq.notEmpty);
        //当请求指令是Sc指令时触发
        MemReq r = reqQ.first;
        reqQ.deq;

        CacheWordSelect sel = getWordSelect(r.addr);
        CacheIndex idx = getIndex(r.addr);
        CacheTag tag = getTag(r.addr);

        if (linkAddr matches tagged Valid .la &&& la == getLineAddr(r.addr)) begin
            if (tagArray[idx] == tag && privArray[idx] > I) begin
                if (privArray[idx] == M) begin
                    hitQ.enq(scSucc);
                    dataArray[idx][sel] <= r.data;
                    refDMem.commit(r, Valid(dataArray[idx]), Valid(scSucc));
                    linkAddr <= Invalid;
                end
                else begin
                    missReq <= r;
                    state <= SendFillReq;
                end
            end
            else begin
                missReq <= r;
                state <= StartMiss;
            end
        end
        else begin
            hitQ.enq(scFail);
            refDMem.commit(r, Invalid, Valid(scFail));
            linkAddr <= Invalid;
        end
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule doFence (state == Ready && reqQ.first.op == Fence && !stq.notEmpty);
    //当请求指令是Fence时触发
        reqQ.deq;
        refDMem.commit(reqQ.first, Invalid, Invalid);
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule startMiss(state == StartMiss);
        CacheWordSelect sel = getWordSelect(missReq.addr);
        CacheIndex idx = getIndex(missReq.addr);
        let tag = tagArray[idx];

        if (privArray[idx] != I) begin
            privArray[idx] <= I;

            //如果是M状态 则需要把缓存行数据提交到内存中
            Maybe#(CacheLine) line;
            if (privArray[idx] == M) begin
                line = tagged Valid dataArray[idx];
            end
            else begin
                line = Invalid;
            end

            let addr = {tag, idx, sel, 2'b0};
            toMem.enq_resp(CacheMemResp{
                child: id,
                addr: addr,
                state: I,
                data: line
                });
        end
        state <= SendFillReq;
        
        if (isValid(linkAddr) && (fromMaybe(?, linkAddr) == getLineAddr(missReq.addr))) begin
            linkAddr <= Invalid;
        end
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule sendFillReq(state == SendFillReq);
        let upg = (missReq.op == Ld || missReq.op == Lr) ? S : M;
        toMem.enq_req(CacheMemReq{
            child: id, 
            addr : missReq.addr, 
            state: upg
            });
        state <= WaitFillResp;
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule waitFillResp(state == WaitFillResp && fromMem.hasResp);
        CacheWordSelect sel = getWordSelect(missReq.addr);
        CacheIndex idx = getIndex(missReq.addr);
        let tag = getTag(missReq.addr);

        //如内存返回值是Resp类型则x接收
        CacheMemResp x = ?;
        case (fromMem.first) matches
            tagged Resp .resp : x = resp;
        endcase

        CacheLine line;
        if (isValid(x.data)) begin
            line = fromMaybe(?, x.data);
        end
        else begin
            line = dataArray[idx];
        end

        Bool check = False;
        if (missReq.op == St) begin
            let old_line = isValid(x.data) ? fromMaybe(?, x.data) : dataArray[idx];
            refDMem.commit(missReq, Valid(old_line), Invalid);
            line[sel] = missReq.data;
            stq.deq;
        end
        else if (missReq.op == Sc) begin

            if (isValid(linkAddr) && fromMaybe(?, linkAddr) == getLineAddr(missReq.addr)) begin
                let old_line = dataArray[idx];
                if (isValid(x.data)) begin
                    old_line = fromMaybe(?, x.data);
                    refDMem.commit(missReq, Valid(old_line), Valid(scSucc));
                    line[sel] = missReq.data;
                    hitQ.enq(scSucc);
                end
            end
            else begin
                hitQ.enq(scFail);
                refDMem.commit(missReq, Invalid, Valid(scFail));
            end

            linkAddr <= Invalid;
        end

        dataArray[idx] <= line;
        tagArray[idx]  <= tag;
        privArray[idx] <= x.state;
        fromMem.deq;
        state <= Resp;
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule sendCore(state == Resp);
        CacheIndex idx = getIndex(missReq.addr);
        CacheWordSelect sel = getWordSelect(missReq.addr);

        if (missReq.op == Ld || missReq.op == Lr) begin
            hitQ.enq(dataArray[idx][sel]);
            refDMem.commit(missReq, Valid(dataArray[idx]), Valid(dataArray[idx][sel]));

            if (missReq.op == Lr) begin
                linkAddr <= tagged Valid getLineAddr(missReq.addr);
            end

        end
        state <= Ready;
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule dng (state != Resp);
        CacheMemReq x = fromMem.first.Req;

        CacheWordSelect sel = getWordSelect(x.addr);
        CacheIndex idx = getIndex(x.addr);
        let tag = getTag(x.addr);

        if (privArray[idx] > x.state) begin
            Maybe#(CacheLine) line;

            if (privArray[idx] == M) begin
                    line = Valid(dataArray[idx]);
            end
            else begin
                    line = Invalid;
            end

            let addr = {tag, idx, sel, 2'b0};
            toMem.enq_resp(CacheMemResp{
                    child: id,
                    addr: addr,
                    state: x.state,
                    data: line
                    });
                privArray[idx] <= x.state;

            if (x.state == I) begin
                linkAddr <= Invalid;
            end
        end

        fromMem.deq;
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule stqToCache (state == Ready && (!reqQ.notEmpty || reqQ.first.op != Ld));
        MemReq r <- stq.issue;

        CacheWordSelect sel = getWordSelect(r.addr);
        CacheIndex idx = getIndex(r.addr);
        CacheTag tag = getTag(r.addr);

        if (tagArray[idx] == tag && privArray[idx] > I) begin
            if (privArray[idx] == M) begin
                dataArray[idx][sel] <= r.data;
                refDMem.commit(r, Valid(dataArray[idx]), Invalid);
                stq.deq;
                if (linkAddr matches tagged Valid .la &&& la == getLineAddr(r.addr))
                    linkAddr <= Invalid;
            end
            else begin
                missReq <= r;
                state <= SendFillReq;
            end
        end
        else begin
            missReq <= r;
            state <= StartMiss;
        end
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    method Action req(MemReq r);
        reqQ.enq(r);
        refDMem.issue(r);
    endmethod
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    method ActionValue#(Data) resp;
        hitQ.deq;
        return hitQ.first;
    endmethod
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------

endmodule