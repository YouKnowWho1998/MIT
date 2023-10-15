import Types::*;
import ProcTypes::*;
import RegFile::*;
import Vector::*;

interface Bht#(numeric type bhtIndex); //定义bht模块接口
    method Addr predPc(Addr pc, Addr predPc);
    method Action update(Addr pc, Bool taken);
endinterface

//==============================================================================================================

module mkBht(Bht#(bhtIndex));
    //bhtIndex的值小于32(取PC值的一部分), 同时bhtEntries的数量是2 ^ bhtIndex
    provisos(Add#(bhtIndex, a__, 32), NumAlias#(TExp#(bhtIndex), bhtEntries));

    //例化生成bhtEntries数量的寄存器阵列组 并赋初始值2'b01(wealyTaken)
    Vector#(bhtEntries, Reg#(Bit#(2))) bhtArr <- replicateM(mkReg(2'b01));    

    //设置2位饱和寄存器上下限
    Bit#(2) maxDp = 2'b11; 
    Bit#(2) minDp = 2'b00; 
//-----------------------------------------------------------------------------------------------------------
//function函数部分

    //getBhtIndex
    //从输入的PC值中截取部分作为bhtIndex(舍弃PC低两位 因为是字对齐)
    function Bit#(bhtIndex) getBhtIndex(Addr pc) = truncate(pc >> 2);

    //getBhtEntry
    //获取特定PC值的Entry值(饱和计数器值)
    function Bit#(2) getBhtEntry(Addr pc) = bhtArr[getBhtIndex(pc)];

    //extractDir
    //dpBits为2'b11和2'b10时为跳转状态 否则为不跳转状态
    function Bool extractDir(Bit#(2) dpBits);
        Bool stronglyTaken = (dpBits == 2'b11);
        Bool weaklyTaken   = (dpBits == 2'b10);
        return (stronglyTaken || weaklyTaken);
    endfunction

    //newDpBits
    //当发生跳转时 dpBits加1 不跳转-1 最高不能超过maxDp 最低不能超过minDp
    function Bit#(2) newDpBits(Bit#(2) dpBits, Bool taken);
        if (taken) begin
            let newDp = dpBits + 1;
            newDp = (newDp == minDp) ? maxDp : newDp;
            return newDp;            
        end
        else begin
            let newDp = dpBits - 1;
            newDp = (newDp == maxDp) ? minDp : newDp; 
            return newDp;                       
        end
    endfunction
//-----------------------------------------------------------------------------------------------------------

    //每次预测都要调用
    method Addr predPc(Addr pc, Addr targetPC);
        let direction = extractDir(getBhtEntry(pc));
        return computeTarget(pc, targetPC, direction);
    endmethod

    //只有预测失败时 才调用update方法对饱和计数器进行更新
    method Action update(Addr pc, Bool taken);
        let index  = getBhtIndex(pc);
        let dpBits = getBhtEntry(pc);
        bhtArr[index] <= newDpBits(dpBits, taken);
    endmethod

endmodule