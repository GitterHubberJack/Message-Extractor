`timescale 1ns / 1ps
module top (
    input clk,
    input rst,
    output logic compare_ok,
    output logic global_compare_ok
);

//local parameters
localparam  MAX_MSG_BYTES = 32;

//local signals
logic [63:0] tdata;
logic [7:0] tkeep;
logic tlast;
logic tvalid;
logic tready;
logic terror;
//
logic msg_valid;
logic [15:0] msg_length; 
logic [8*MAX_MSG_BYTES-1:0] msg_data;
logic msg_error;
//
logic clk_w, clk_sim;
logic rst_w, rst_sim;
//
logic [15:0] counter1;
logic [15:0] counter2;
logic [8*MAX_MSG_BYTES-1:0] msg_data_r;
logic [8*MAX_MSG_BYTES-1:0] expected_data;
//define memories to store the encoded data and the expedted data after decoding
logic [63 : 0] encoded_data_rom [0:23] ;
logic [10 : 0] ctrl_signals [0:23] ;
logic [8*MAX_MSG_BYTES -1 : 0] expected_data_rom [0:12] ;

//Initialize memories. Initilization files are based on the example provided
//along the assignment
initial begin
    $readmemh("../mem_files/encoded_data_rom.mem", encoded_data_rom);
    $readmemb("../mem_files/ctrl_signals.mem", ctrl_signals);
    $readmemh("../mem_files/expected_data_rom.mem", expected_data_rom);
end

`ifdef __SIMULATION__
initial begin
    clk_sim = 0;
    forever #25 clk_sim = ~clk_sim;
end

initial begin
    rst_sim = 1;
    #1000 rst_sim = 0;
end
`endif

`ifdef __SIMULATION__
     assign clk_w = clk_sim; 
     assign rst_w = rst_sim;
`else
    assign clk_w = clk ; 
    assign rst_w = rst;   
`endif
  
always@(posedge clk_w) begin
    if (rst_w) begin
        counter1 <= 0;
        counter2 <= 0;
        terror   <= 0;
        tkeep   <= '0;
        tlast   <= 0;
        tvalid  <= 0;
        tdata   <= '0;
        msg_data_r <= '0;
        expected_data <= '0;
        compare_ok <= 1;
        global_compare_ok <= 1;
    end else begin
        msg_data_r <= msg_data;
        if (counter1 == 0) begin
            $display("=============================");
            $display("Starting the 1st test");
            $display("=============================");
        end

        if ((counter1 < 24) & tready) begin
            counter1 <= counter1 + 1;
            terror  <= ctrl_signals[counter1][0]; 
            tkeep   <= ctrl_signals[counter1][8 : 1]; 
            tlast   <= ctrl_signals[counter1][9]; 
            tvalid  <= ctrl_signals[counter1][10]; 
            //
            tdata   <= encoded_data_rom[counter1];
        end else begin
            terror   <= 0;
            tkeep   <= '0;
            tlast   <= 0;
            tvalid  <= 0;
            tdata   <= '0;
        end
        if (msg_valid & (counter2 < 14)) begin
            $display("counter2 = %d  ;  compare_ok = %b  ;  global_compare_ok = %b", counter2, compare_ok, global_compare_ok);
            expected_data <= expected_data_rom[counter2];
            global_compare_ok   <= global_compare_ok & (expected_data == msg_data_r);
            compare_ok          <= (expected_data == msg_data_r);
            counter2 <= counter2 +1;
        end else  if (counter2 >= 11) begin
           expected_data   <= 0;
        end
        
        if (counter1 == 21) begin
            $display("=============================");
            $display("Starting the 2nd test");
            $display("=============================");
        end
    end
end

msg_parser # (
    .MAX_MSG_BYTES(MAX_MSG_BYTES)
) msg_parser_inst (
    .clk(clk_w),
    .rst(rst_w),
    //
    .s_tuser(terror),
    .s_tkeep(tkeep),
    .s_tlast(tlast),
    .s_tvalid(tvalid),
    .s_tdata(tdata),
    //
    .s_tready(tready),
    .msg_valid(msg_valid),
    .msg_data(msg_data),
    .msg_length(msg_length),
    .msg_error(msg_error)
);

endmodule
