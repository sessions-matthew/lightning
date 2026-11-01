// systemverilog adder module

module adder (
    input logic [3:0] a,
    input logic [3:0] b,
    output logic [3:0] sum,
    output logic carry
);
    assign {carry, sum} = a + b;
endmodule