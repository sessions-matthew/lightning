// systemverilog adder testbench

module tb_adder;
    reg [3:0] a;
    reg [3:0] b;
    wire [3:0] sum;
    wire carry;
    adder uut (
        .a(a),
        .b(b),
        .sum(sum),
        .carry(carry)
    );
    initial begin
        // $monitor("a = %d, b = %d, sum = %d, carry = %d", a, b, sum, carry);
        $dumpfile("sim.vcd");
        $dumpvars(0, tb_adder);
        a = 4'b0;
        b = 4'b0;
        #10;
        a = 4'b1;
        b = 4'b1;
        #10;
        a = 4'b10;
        b = 4'b11;
        #10;
        a = 4'b100;
        b = 4'b101;
        #10;
        a = 4'b1000;
        b = 4'b1001;
        $display("test completed");
        #100;
        $finish;
    end
endmodule