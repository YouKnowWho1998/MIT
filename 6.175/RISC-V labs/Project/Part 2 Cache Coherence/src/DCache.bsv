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


//================================================================= DCache =======================================================================================

// cache <-> mem message
// typedef struct{
//     CoreID            child; 
//     Addr              addr;
//     MSI               state;
//     Maybe#(CacheLine) data;
// } CacheMemResp deriving(Eq, Bits, FShow);

// typedef struct{
//     CoreID      child;
//     Addr        addr;
//     MSI         state;
// } CacheMemReq deriving(Eq, Bits, FShow);

// interface MessageGet;
//   method Bool hasResp;
//   method Bool hasReq;
//   method Bool notEmpty;
//   method CacheMemMessage first;
//   method Action deq;
// endinterface

// interface MessagePut;
//   method Action enq_resp(CacheMemResp d);
//   method Action enq_req(CacheMemReq d);
// endinterface

module mkDCache#(CoreID id)(
    MessageGet fromMem,//Router -> Cache //downgrade requests and upgrade responses
    MessagePut toMem, //Cache -> Router  //upgrade requests and downgrade responses
    RefDMem    refDMem,//用于调试
    DCache     ifc//接口
); 

    Fifo#(2, Data)	    hitQ 	 <- mkBypassFifo;//是否命中状态
    Fifo#(1, MemReq)    reqQ     <- mkBypassFifo;//来自处理器的所有请求将首先进入reqQ队列
    Reg#(MemReq)        missReq  <- mkRegU;//未命中请求      
    Reg#(CacheStatus)   state    <- mkReg(Ready);//Cache状态机
    Reg#(Maybe#(CacheLineAddr)) lineAddr <- mkReg(Invalid); //该寄存器记录lr.w保留的缓存行地址（如果该寄存器有效）

    //Data部分阵列
    Vector#(CacheRows, Reg#(CacheLine)) dataArray <- replicateM(mkRegU);

    //Tag部分阵列
    Vector#(CacheRows, Reg#(CacheTag))  tagArray  <- replicateM(mkRegU);

    //MSI标识位部分阵列
    Vector#(CacheRows, Reg#(MSI))  privArray <- replicateM(mkReg(I));

//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule doReq(state == Ready);
        MemReq r = reqQ.first;
        reqQ.deq;

        CacheWordSelect sel = getWordSelect(r.addr);
        CacheIndex idx = getIndex(r.addr);
        CacheTag tag = getTag(r.addr);

        //tag位相符且不为I状态时 表示指令命中
        let hit = False;
        if (tagArray[idx] == tag && privArray[idx] > I) begin
            hit = True;
        end

        // 当处理Sc请求时，我们首先检查linkAddr中的保留地址是否与Sc请求访问的地址匹配。如果 
        // linkAddr无效或地址不匹配，我们直接向核心响应值1，指示存储条件操作失败。否则，我们
        // 将继续将其作为St请求进行处理。                                                   
        let proceed = False; //默认为False
        if (r.op == Sc) begin
            if (isValid(linkAddr)) begin
                if (fromMaybe(?, linkAddr) == getLineAddr(r.addr)) begin
                    proceed = True;
                end
            end
        end
        else begin
            proceed = True;
        end

        if (!proceed) begin
            hitQ.enq(scFail);
            refDMem.commit(r, Invalid, Valid(scFail));
            linkAddr <= Invalid;
        end
        else begin
            if (hit) begin
                if (r.op == Ld || r.op == Lr) begin
                    hitQ.enq(dataArray[idx][sel]);
                    refDMem.commit(r, Valid(dataArray[idx]), Valid(dataArray[idx][sel]));
                    //Lr可以像Ld请求一样在DCache中处理, 当该请求完成处理时,它会将linkAddr设置为Valid（已访问缓存行地址）
                    if (r.op == Lr) begin
                        linkAddr <= tagged Valid getLineAddr(r.addr);
                    end
                end
                //如果不是读取指令 则是写入指令
                else begin
                    //如果它命中缓存(即缓存行处于M状态)，将写入数据数组，并用值0响应CPU，表示Sc操作成功
                    //只要M状态才可写入 S状态只能读取 I状态既不能写入也不能读取
                    if (privArray[idx] == M) begin
                        dataArray[idx][sel] <= r.data;
                        //当指令是Sc时较为特殊,常量ScFail和ScSucc来表示Sc请求的返回值
                        //当Sc请求处理完成时，无论成功还是失败，它总是将linkAddr设置为Invalid标签
                        if (r.op == Sc) begin
                            hitQ.enq(scSucc);
                            refDMem.commit(r, Valid(dataArray[idx]), Valid(scSucc));
                            linkAddr <= Invalid;
                        end
                        else begin
                            refDMem.commit(r, Valid(dataArray[idx]), Invalid);
                        end
                    end
                    //如果命中但缓存行不是M状态 跳转到SendFillReq操作 请求upgrade到M状态
                    else begin
                        missReq <= r;
                        state <= SendFillReq;
                    end
                end
            end
            //如果未命中缓存 则进行未命中操作(startMiss)
            else begin
                missReq <= r;
                state <= StartMiss;
            end
        end
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule startMiss(state == StartMiss);
        CacheWordSelect sel = getWordSelect(missReq.addr);
        CacheIndex idx = getIndex(missReq.addr);
        let tag = tagArray[idx];

        // write-back (Evacuate)
        if (privArray[idx] != I) begin
            privArray[idx] <= I;

            //如果本核心的缓存行是M状态 则需要把数据写回内存 供其他核心读取 
            Maybe#(CacheLine) line;
            if (privArray[idx] == M) begin
                line = tagged Valid dataArray[idx];
            end
            else begin
                line = Invalid;
            end
    
            let addr = {tag, idx, sel, 2'b0};
            //通过toMem这个MessageFIFO的enq.resp子FIFO接口传出
            toMem.enq_resp(CacheMemResp{ //downgrade Response
                child: id,
                addr: addr,
                state: I,
                data: line
                });
        end
        state <= SendFillReq;
        
        //如果未命中指令的地址与Lr标记的地址一样 则立刻变成Invalid
        if (isValid(linkAddr) && (fromMaybe(?, linkAddr) == getLineAddr(missReq.addr))) begin
            linkAddr <= Invalid;
        end
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule sendFillReq(state == SendFillReq);
        //如果是写入指令则请求跳转到M状态 如果是读取指令(从内存中读)则请求跳转到S状态
        let upgrade = (missReq.op == Ld || missReq.op == Lr) ? S : M; //请求upgrade的状态
        //通过toMem这个MessageFIFO的enq.req子FIFO接口传出
        toMem.enq_req(CacheMemReq{//upgrade request
            child: id, 
            addr : missReq.addr, 
            state: upgrade
            });
        state <= WaitFillResp;
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule waitFillResp(state == WaitFillResp && fromMem.hasResp);
        CacheWordSelect sel = getWordSelect(missReq.addr);
        CacheIndex idx = getIndex(missReq.addr);
        let tag = getTag(missReq.addr);

        //如内存返回值是Resp类型则用x接收
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
            //如果未命中指令是St 缓存行首先被内存传过来的数据更新 其次将指令数据写入缓存行对应的word位置
            let old_line = isValid(x.data) ? fromMaybe(?, x.data) : dataArray[idx];
            refDMem.commit(missReq, Valid(old_line), Invalid);
            line[sel] = missReq.data;
        end
        else if (missReq.op == Sc) begin
            //如果是Sc指令 则首先检查标记位是否对应且为Valid 
            if (isValid(linkAddr) && fromMaybe(?, linkAddr) == getLineAddr(missReq.addr)) begin
                let old_line = dataArray[idx];
                if (isValid(x.data)) begin
                    old_line = fromMaybe(?, x.data);
                    refDMem.commit(missReq, Valid(old_line), Valid(scSucc));
                    line[sel] = missReq.data;
                    hitQ.enq(scSucc);
                end
            end
            //如果不对应则上报scFail信息
            else begin
                hitQ.enq(scFail);
                refDMem.commit(missReq, Invalid, Valid(scFail));
            end
            //操作完成后将标记位清空
            linkAddr <= Invalid;
        end

        //更新从内存传过来的数据
        dataArray[idx] <= line;
        tagArray[idx]  <= tag;
        privArray[idx] <= x.state;
        fromMem.deq;
        state <= Resp;
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule sendToCore(state == Resp);
        CacheIndex idx = getIndex(missReq.addr);
        CacheWordSelect sel = getWordSelect(missReq.addr);

        //从内存更新完数据之后 如果是Ld或者Lr指令将数据读取
        if (missReq.op == Ld || missReq.op == Lr) begin
            hitQ.enq(dataArray[idx][sel]);
            refDMem.commit(missReq, Valid(dataArray[idx]), Valid(dataArray[idx][sel]));

            //Lr指令会额外设定Valid位
            if (missReq.op == Lr) begin
                linkAddr <= tagged Valid getLineAddr(missReq.addr);
            end
        end
        state <= Ready;
    endrule
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule downGrade (state != Resp); //只在处在非响应状态下才会触发
        CacheMemReq x = ?;
        //x接收上级传来的req请求数据(降级)
        case (fromMem.first) matches
            tagged Req .req : x = req;
        endcase

        CacheWordSelect sel = getWordSelect(x.addr);
        CacheIndex idx = getIndex(x.addr);
        let tag = getTag(x.addr);

        //当前缓存行MSI状态较高时
        if (privArray[idx] > x.state) begin
            Maybe#(CacheLine) line;

            //写回操作（write-back）Evacuate
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
            //写回内存之后进行downgrade
            privArray[idx] <= x.state;

            //如果downgrade是I状态 则Lr地址标识位也是Invalid
            if (x.state == I) begin
                linkAddr <= Invalid;
            end
        end
        fromMem.deq;
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