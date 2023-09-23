import vector :: *;

//=============================================================================================================
//练习6 答：

function Bit#(32) shiftright(Bit#(1) en, Bit(32) in, Integer n); 
    Bit#(32) out = 0;
    if(en == 1'b0)
        return in;
    else begin
        for(Integer i = 0, i < 32, i = i + 1) begin
            if(i + 2**n < 32)
                out[i] = in[i + 2**n]; 
            else
                out = 0; 
            end 
        return out ; 
    end        
endfunction


function Bit#(32) barrelshiftright(Bit#(32) in, Bit#(5) shiftBy);
    Vector#(6, Bit#(32)) out;
    out[0] = in;
    for(Integer i = 0, i < 5, i = i + 1) begin
        out[i + 1] = shiftright (shiftBy[i], out[i], i);
    end
    return out[5]; 
endfunction





















/*
function Bit#(32) shiftRightPow2(Bit#(1) en, Bit#(32) unshifted, Integer power);
    Integer distance = 2**power;
    Bit#(32) shifted = 0;
    if(en == 0) 
        return unshifted;
    else begin
        for(Integer i = 0; i < 32; i = i + 1) begin
            if(i + distance < 32) begin
                shifted[i] = unshifted[i + distance];end end
        return shifted; end
endfunction


function Bit#(32) barrelShifterRight(Bit#(32) in, Bit#(5) shiftBy);
    Vector#(6, Bit#(32)) vec;
    vec[0] = in;
    for(Integer i = 0; i < 5; i = i + 1) begin
        vec[i + 1] = shiftRightPow2(shiftBy[i], vec[i], i); end
    return vec[5];
endfunction