import Multipliers::*;


//=============================================================================================================
//练习1：

(* synthesize *)
module mkTbSignedVsUnsigned();
    function Bit#(16) test_function(Bit#(8) a, Bit#(8) b) = multiply_signed(a, b); endfunction
    Empty tb <- mkTbMulFunction(test_function, multiply_signed, True);
    return tb;
endmodule

//=============================================================================================================
//练习3：

(* synthesize *)
module mkTbEx3();
    function Bit#(16) func(Bit#(8) a, Bit#(8) b) = multiply_by_adding(a, b); endfunction
    Empty tb <- mkTbMulFunction(func, multiply_unsigned, True);
    return tb;
endmodule

//=============================================================================================================
//练习5：

(* synthesize *)
module mkTbEx5();
    Empty tb <- mkTbMulModule(folded_multiplier, multiply_by_adding(), True);
    return tb;
endmodule

//=============================================================================================================
//练习7：

(* synthesize *)
module mkTbEx7a();
    function Bit#(8) boothmultiply2(Bit#(4) a, Bit#(4) b) = radix_2_boothmultiplier(a, b); endfunction
    Empty tb <- mkTbMulModule(boothmultiply2, multiply_signed, True);
    return tb;
endmodule

(* synthesize *)
module mkTbEx7b();
    function Bit#(16) boothmultiply2(Bit#(8) a, Bit#(8) b) = radix_2_boothmultiplier(a, b); endfunction
    Empty tb <- mkTbMulModule(boothmultiply2, multiply_signed, True);
    return tb;
endmodule

//=============================================================================================================
//练习9：

(* synthesize *)
module mkTbEx9a();
    function Bit#(32) boothmultiply4(Bit#(16) a, Bit#(16) b) = radix_4_boothmultiplier(a, b); endfunction
    Empty tb <- mkTbMulModule(boothmultiply4, multiply_signed, True);
    return tb;
endmodule

(* synthesize *)
module mkTbEx9b();
    function Bit#(64) boothmultiply4(Bit#(32) a, Bit#(32) b) = radix_4_boothmultiplier(a, b); endfunction
    Empty tb <- mkTbMulModule(boothmultiply4, multiply_signed, True);
    return tb;
endmodule




