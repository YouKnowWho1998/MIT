import adders :: *;

function Bit#(TAdd#(n,n)) multiply_unsigned(Bit#(n) a, Bit#(n) b);
    UInt#(n) a_uint = unpack(a);
    UInt#(n) b_uint = unpack(b);
    UInt#(TAdd#(n,n)) product_uint = zeroExtend(a_uint) * zeroExtend(b_uint);
    return pack(product_uint);
endfunction


function Bit#(TAdd#(n,n)) multiply_signed(Bit#(n) a, Bit#(n) b);
    Int#(n) a_int = unpack(a);
    Int#(n) b_int = unpack(b);
    Int#(TAdd#(n,n)) product_int = signExtend(a_int) * signExtend(b_int);
    return pack(product_int);
endfunction



//=============================================================================================================
//练习2：

function Bit#(TAdd#(n,n)) multiply_by_adding(Bit#(n) a, Bit#(n) b);
    Bit#(n) tp = 0;
    Bit#(n) prod = 0;
    for(Integer i = 0; i < valueOf(n); i = i + 1) begin
        Bit#(n) m = (a[i] == 0) ? 0 : b;
        Bit#(TAdd#(n,1)) sum = addN (m, tp, 0);
        prod[i] = sum[0];
        tp = sum[valueOf(TAdd#(n,1)) : 1];
    end
    return {tp, prod};
endfunction


//=============================================================================================================
//练习4：

function Bit#(TAdd#(n,n)) folded_multiplier(Bit#(n) a, Bit#(n) b);
    Reg#(Bit#(n)) a <- mkRegU();
    Reg#(Bit#(n)) b <- mkRegU();
    Reg#(Bit#(n)) prod <- mkRegU();
    Reg#(Bit#(n)) tp <- mkReg(0);
    Reg#(Bit#(n)) i <- mkReg(valueOf(n));
    rule mulStep;
        if (i < valueOf(n)) begin
            Bit#(n) m = (a[i] == 0) ? 0 : b;
            Bit#(TAdd#(n,1)) sum = addN (m, tp, 0);
            prod[i] <= sum[0];
            tp <= sum[valueOf(n):1];
            i <= i + 1;
        end
    endrule
    return {tp, prod};    
endfunction


//=============================================================================================================
//练习6：

function Bit#(TAdd#(n,n)) radix_2_boothmultiplier(Bit#(n) a, Bit#(n) b); //a和b都是补码
    Bit#(TAdd#(n,n)) sum = 0;
    Bit#(TAdd#(n,1)) p = {b, 1'b0} ; 
    for(Integer i = 0; i < valueOf(n); i = i + 1) begin
        if(p[1:0] == 2'b01)
            sum = sum + a*2**i;
        if(p[1:0] == 2'b10)
            sum = sum - a*2**i;
        if(p[1:0] == 2'b11 || p[1:0] == 2'b00)
            sum = sum;
        p = p >> 1;
    end
    return sum;
endfunction


//=============================================================================================================
//练习8：

function Bit#(TAdd#(n,n)) radix_4_boothmultiplier(Bit#(n) a, Bit#(n) b); //a和b都是补码
    Bit#(TAdd#(n,n)) sum = 0;
    Bit#(TAdd#(n,2)) p = {msb(b), b, 1'b0} ; 
    for(Integer i = 0; i < valueOf(n / 2); i = i + 1) begin
        case(b[2:0]) matches
            3'b000: sum = sum;
            3'b001: sum = sum + a*(2**(2**i));
            3'b010: sum = sum + a*(2**(2**i));
            3'b011: sum = sum + (a*(2**(2**i)) << 1);
            3'b100: sum = sum - (a*(2**(2**i)) << 1);
            3'b101: sum = sum - a*(2**(2**i));
            3'b110: sum = sum - a*(2**(2**i));
            3'b111: sum = sum;
        endcase
        p = p >> 2;
    end
    return sum;
endfunction







