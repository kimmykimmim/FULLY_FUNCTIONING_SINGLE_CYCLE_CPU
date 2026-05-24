///////////////////////////////////////////////////////////////////////////
// MODULE: CPU for TSC microcomputer: cpu.v
// Author: 
// Description: 

// DEFINITIONS

`define WORD_SIZE 16    // data and address word size

// MODULE DECLARATION
module cpu (
    output readM,                       // read from memory
    output [`WORD_SIZE-1:0] address,    // current address for data
    inout [`WORD_SIZE-1:0] data,        // data being input or output
    input inputReady,                   // indicates that data is ready from the input port
    input reset_n,                      // active-low RESET signal
    input clk,                          // clock signal
  
    // for debuging/testing purpose
    output [`WORD_SIZE-1:0] num_inst,   // number of instruction during execution
    output [`WORD_SIZE-1:0] output_port // this will be used for a "WWD" instruction 
);
// 1. 명령어 페치
    assign readM = 1'b1;
    wire [`WORD_SIZE-1:0] pc_out;
    assign address = pc_out;

    reg [`WORD_SIZE-1:0] instruction;
    always @(*) begin               // inputReady 구간에 data를 래치
        if (inputReady) instruction = data;
    end

    // 2. 필드 분해
    wire [1:0]  rs     = instruction[11:10];
    wire [1:0]  rt     = instruction[9:8];
    wire [1:0]  rd     = instruction[7:6];
    wire [7:0]  imm    = instruction[7:0];
    wire [11:0] target = instruction[11:0];

    // 3. Control Unit
    wire RegWrite, RegDst, ALUSrc, isLHI, isJMP, isWWD;
    wire [2:0] ALUOp;
    ControlUnit CU (
        .instruction(instruction),
        .RegWrite(RegWrite), .RegDst(RegDst), .ALUSrc(ALUSrc),
        .ALUOp(ALUOp), .isLHI(isLHI), .isJMP(isJMP), .isWWD(isWWD)
    );

    // 4. Register File  (RF는 active-high reset이므로 ~reset_n)
    wire [1:0] write_addr = RegDst ? rd : rt;       // RegDst MUX
    wire [`WORD_SIZE-1:0] reg_data1, reg_data2, write_data;
    RF rf (
        .addr1(rs), .addr2(rt), .addr3(write_addr),
        .data3(write_data), .write(RegWrite),
        .clk(clk), .reset(~reset_n),
        .data1(reg_data1), .data2(reg_data2)
    );

    // 5. ALU
    wire [`WORD_SIZE-1:0] sign_ext = {{8{imm[7]}}, imm};        // 부호확장
    wire [`WORD_SIZE-1:0] alu_B = ALUSrc ? sign_ext : reg_data2; // ALUSrc MUX
    wire [`WORD_SIZE-1:0] alu_C; wire alu_Cout;
    ALU alu (
        .A(reg_data1), .B(alu_B), .Cin(1'b0),
        .OP({1'b0, ALUOp}),         // 3비트 ALUOp -> 4비트 OP (ADD=0)
        .Cout(alu_Cout), .C(alu_C)
    );

    // 6. Write-back MUX (LHI vs ALU)
    wire [`WORD_SIZE-1:0] lhi_val = {imm, 8'b0};
    assign write_data = isLHI ? lhi_val : alu_C;

    // 7. PC
    PC pc (
        .clk(clk), .reset_n(reset_n),
        .isJMP(isJMP), .jump_target(target),
        .pc_out(pc_out)
    );
    reg [`WORD_SIZE-1:0] num_inst_r;
    reg [`WORD_SIZE-1:0] output_port_r;

    assign num_inst    = num_inst_r;
    assign output_port = output_port_r;
    // 8. num_inst / output_port
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            num_inst_r    <= 16'b0;
            output_port_r <= 16'b0;
        end else begin
            num_inst_r <= num_inst_r + 1;
            if (isWWD) output_port_r <= reg_data1;   // WWD $rs
        end
    end
  
endmodule

`define OPCODE_R    4'd15
`define OPCODE_ADI  4'd4
`define OPCODE_LHI  4'd6
`define OPCODE_JMP  4'd9

`define FUNC_ADD    6'd0
`define FUNC_WWD    6'd28

module PC (
    input                       clk,
    input                       reset_n,       // active-low reset
    input                       isJMP,         // from Control Unit
    input  [11:0]               jump_target,   // instruction[11:0]
    output reg [`WORD_SIZE-1:0] pc_out         // current PC value
);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            // ---- Reset: PC starts from address 0 ----
            pc_out <= 16'b0;
        end
        else begin
            if (isJMP) begin
                // ---- JMP: PC <- {PC[15:12], target[11:0]} ----
                pc_out <= {pc_out[15:12], jump_target};
            end
            else begin
                // ---- Normal: PC <- PC + 1 ----
                pc_out <= pc_out + 1;
            end
        end
    end

endmodule


module ControlUnit (
    input  [`WORD_SIZE-1:0] instruction,  // 16-bit instruction from memory
    
    output reg       RegWrite,
    output reg       RegDst,
    output reg       ALUSrc,
    output reg [2:0] ALUOp,
    output reg       isLHI,
    output reg       isJMP,
    output reg       isWWD
);

    // ---- Extract fields from instruction ----
    wire [3:0] opcode;
    wire [5:0] func;
    
    assign opcode = instruction[15:12];
    assign func   = instruction[5:0];

    always @(*) begin
        // ---- Default values ----
        RegWrite = 1'b0;
        RegDst   = 1'b0;
        ALUSrc   = 1'b0;
        ALUOp    = 3'b000;
        isLHI    = 1'b0;
        isJMP    = 1'b0;
        isWWD    = 1'b0;
        
        case (opcode)
            `OPCODE_R: begin
                case (func)
                    `FUNC_ADD: begin
                        RegWrite = 1'b1;
                        RegDst   = 1'b1;
                        ALUSrc   = 1'b0;
                        ALUOp    = 3'b000;
                    end
                    `FUNC_WWD: begin
                        isWWD    = 1'b1;
                    end
                endcase
            end
            
            `OPCODE_ADI: begin
                RegWrite = 1'b1;
                RegDst   = 1'b0;
                ALUSrc   = 1'b1;
                ALUOp    = 3'b000;
            end
            
            `OPCODE_LHI: begin
                RegWrite = 1'b1;
                RegDst   = 1'b0;
                isLHI    = 1'b1;
            end
            
            `OPCODE_JMP: begin
                isJMP    = 1'b1;
            end
        endcase
    end

endmodule



module RF(
    input [1:0] addr1,
    input [1:0] addr2,
    input [1:0] addr3,
    input [15:0] data3,
    input write,
    input clk,
    input reset,
    output reg [15:0] data1,
    output reg [15:0] data2
    );
    // FILLME
    
    
    reg [15:0] reg1,reg2,reg3,reg4;
    wire y1,y2,y3,y4;
    assign y1=((~addr3[0])&(~addr3[1]))&write;
    assign y2=((addr3[0])&(~addr3[1]))&write;
    assign y3=((~addr3[0])&(addr3[1]))&write;
    assign y4=((addr3[0])&(addr3[1]))&write;
    
    
    always@(posedge clk) begin
     if(reset) begin
        reg1 <= 0;
        reg2 <= 0;
        reg3 <= 0;
        reg4 <= 0;
    end
    else begin
        if(y1) reg1 <= data3;
        if(y2) reg2 <= data3;
        if(y3) reg3 <= data3;
        if(y4) reg4 <= data3;
    end
    end
    
    
    always@(reg1,reg2,reg3,reg4,addr1)begin
    if(!addr1[0]&!addr1[1]) data1= reg1;
    if(addr1[0]&!addr1[1])data1= reg2;
    if(!addr1[0]&addr1[1])data1= reg3;
    if(addr1[0]&addr1[1])data1= reg4;
    end
    
    always@(reg1,reg2,reg3,reg4,addr2)begin
    if(!addr2[0]&!addr2[1]) data2= reg1;
    if(addr2[0]&!addr2[1])data2= reg2;
    if(!addr2[0]&addr2[1])data2= reg3;
    if(addr2[0]&addr2[1])data2= reg4;
    end
    
endmodule



module ALU(
    input [15:0] A,
    input [15:0] B,
    input Cin,
    input [3:0] OP,
    output reg Cout,
    output reg [15:0] C
    );
    
    // FILLME
`define	OP_ADD	4'b0000
`define	OP_SUB	4'b0001
//  Bitwise Boolean operation
`define	OP_ID	4'b0010
`define	OP_NAND	4'b0011
`define	OP_NOR	4'b0100
`define	OP_XNOR	4'b0101
`define	OP_NOT	4'b0110
`define	OP_AND	4'b0111
`define	OP_OR	4'b1000
`define	OP_XOR	4'b1001
// Shifting
`define	OP_LRS	4'b1010
`define	OP_ARS	4'b1011
`define	OP_RR	4'b1100
`define	OP_LLS	4'b1101
`define	OP_ALS	4'b1110
`define	OP_RL	4'b1111
always @(*) begin
        Cout = 0;  // default
        C = 0;

        case (OP)
            // Arithmetic
            `OP_ADD: begin
                {Cout, C} = A + B + Cin;
            end

            `OP_SUB: begin
                {Cout, C} = A +(~B+1) - Cin;
            end

            // Bitwise
            `OP_ID:   C = A;
            `OP_NAND: C = ~(A & B);
            `OP_NOR:  C = ~(A | B);
            `OP_XNOR: C = ~(A ^ B);
            `OP_NOT:  C = ~A;
            `OP_AND:  C = A & B;
            `OP_OR:   C = A | B;
            `OP_XOR:  C = A ^ B;

            // Shifts
            `OP_LRS: begin
                C = A >> 1;
            end

            `OP_ARS: begin
                C = $signed(A) >>> 1;
            end

            `OP_LLS: begin
                C = A << 1;
            end

            `OP_ALS: begin
                C = A <<< 1; 
            end

            // Rotate
            `OP_RR: begin
                C = {A[0], A[15:1]};
            end

            `OP_RL: begin
                C = {A[14:0], A[15]};
            end

            default: begin
                C = 16'h0000;
            end
        endcase
    end
    
endmodule