
function Bit#(1) multiplexer1(Bit#(1) sel, Bit#(1) a, Bit#(1) b);
    return (sel == 0)? a: b;
endfunction

//=============================================================================================================
//练习1 答：需要2个与门，1个或门,1个非门。

function Bit#(1) and1(Bit#(1) a, Bit#(1) b); //与门
    return a & b;
endfunction


function Bit#(1) or1(Bit#(1) a, Bit#(1) b); //或门
    return a | b;
endfunction


function Bit#(1) not1(Bit#(1) a); //非门
    return ~a;
endfunction


function Bit#(1) multiplexer1(Bit#(1) sel, Bit#(1) a, Bit#(1) b);
    return or1(and1(not1(sel),a), and1(sel,b));
endfunction

//=============================================================================================================
//练习2 答：

function Bit#(5) multiplexer5(Bit#(1) sel, Bit#(5) a, Bit#(5) b);
    Bit#(5) out;
    for(Integer i = 0; i < 5; i = i + 1) begin
        out[i] = multiplexer1(sel, a[i], b[i]); 
    end
    return out;
endfunction

//=============================================================================================================
//练习3 答：

function Bit#(n) multiplexern(Bit#(1) sel, Bit#(n) a, Bit#(n) b);
    Bit#(n) out;
    for(Integer i = 0, i < valueOf(n), i = i + 1) begin
        out[i] = multiplexer1(sel, a[i], b[i]) 
    end
    return out;
endfunction



//=============================================================================================================













