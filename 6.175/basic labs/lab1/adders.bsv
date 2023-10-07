import multiplexers :: *;

//=============================================================================================================
//练习4 答:

function Bit#(1) fa_sum(Bit#(1) a, Bit#(1) b, Bit#(1) c);
    return a ^ b ^ c;
endfunction


function Bit#(1) fa_carry(Bit#(1) a, Bit#(1) b, Bit#(1) c);
    return (a & b) | (c & (a ^ b));
endfunction


function Bit#(5) add4(Bit#(4) a, Bit#(4) b, Bit#(1) c0);
    Bit#(4) s;
    Bit#(1) c = c0;
    for(Integer i = 0; i < 4; i = i + 1) begin
        s[i] = fa_sum(a[i], b[i], c);
        c    = fa_carry(a[i], b[i], c); end //c的值每周期刷新
    return {c,s};
endfunction

//=============================================================================================================
//练习5 答：

//addN n位纹波进位加法器
function Bit#(TAdd#(n,1)) addN(Bit#(n) a, Bit#(n) b, Bit#(1) c0);
    Bit#(n) s;
    Bit#(1) c = c0;
    for(Integer i = 0; i < valueOf(n); i = i + 1) begin
        s[i] = fa_sum(a[i], b[i], c);
        c    = fa_carry(a[i], b[i], c); 
    end
    return {c,s};
endfunction


//5位纹波进位加法器
function Bit#(5) add4(Bit#(4) a, Bit#(4) b, Bit#(1) c0) = addN(a, b, c0); endfunction



//8位进位选择加法器
function Bit#(9) Adder8(Bit#(8) a, Bit#(8) b, Bit#(1) cin);
    Bit#(8) s = 0;
    Bit#(1) c = 0;
    let low_add4   = add4 (a[3:0], b[3:0], cin);
    let high1_add4 = add4 (a[7:4], b[7:4], 1'b0);
    let high2_add4 = add4 (a[7:4], b[7:4], 1'b1);
    let high_sum   = multiplexer1 (low_add4[4], high2_add4[3:0], high1_add4[3:0]);
    c = multiplexer1 (low_add4[4], high2_add4[4], high1_add4[4]);
    s = {high_sum,low_add4[3:0]};
    return {c,s};
endfunction




















