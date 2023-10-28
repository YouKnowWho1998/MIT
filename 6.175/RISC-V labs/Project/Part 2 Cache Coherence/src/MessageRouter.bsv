import Vector::*;
import CacheTypes::*;
import MessageFifo::*;
import Types::*;

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

//==============================================================================================================================================================
module mkMessageRouter(Vector#(CoreNum, MessageGet) c2r,//L1 DCache -> Router
                        Vector#(CoreNum, MessagePut) r2c,//Router -> L1 DCache
                        MessageGet m2r, //Memory(Parent Protocol Processor) -> Router
                        MessagePut r2m, //Router -> Memory(Parent Protocol Processor)
                        Empty ifc //空接口
                        );

    // typedef `CORE_NUM CoreNum;
    // typedef Bit#(TLog#(CoreNum)) CoreID;
    Reg#(CoreID) start_core <- mkReg(0);//从第X号核心开始
    CoreID max_core = fromInteger(valueOf(CoreNum) - 1);

//-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule coreTomem;
        CoreID core_select = 0;
        Bool found_msg  = False;
        Bool found_resp = False;

        for (Integer i = 0; i < valueOf(CoreNum); i = i + 1) begin
            CoreID core_i;
            if (start_core <= max_core - fromInteger(i)) begin
                core_i = start_core + fromInteger(i);
            end
            else begin
                core_i = start_core - fromInteger(valueOf(CoreNum) - i);
            end

            if (c2r[core_i].notEmpty) begin
                CacheMemMessage x = c2r[core_i].first;
                if (x matches tagged Resp .r &&& !found_resp) begin
                    core_select = core_i;
                    found_resp = True;
                    found_msg = True;
                end
                else if (!found_msg) begin
                    core_select = core_i;
                    found_msg = True;
                end
            end
        end

            if (found_msg) begin
                CacheMemMessage x = c2r[core_select].first;
                case (x) matches
                    tagged Resp .resp : r2m.enq_resp(resp);
                    tagged Req .req : r2m.enq_req(req);
                endcase
                c2r[core_select].deq;
            end

            if (start_core == max_core) begin
                start_core <= 0;
            end
            else begin
                start_core <= start_core + 1;
            end
    endrule
//-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
    rule mem2core;
        let x = m2r.first;
        m2r.deq;
        case (x) matches
            tagged Resp .resp : r2c[resp.child].enq_resp(resp);
            tagged Req  .req  : r2c[req.child].enq_req(req);
        endcase
    endrule
//-----------------------------------------------------------------------------------------------------------------------------------------------------------------------

endmodule   