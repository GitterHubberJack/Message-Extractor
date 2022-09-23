`timescale 1ns / 1ps
module msg_parser #(
    parameter MAX_MSG_BYTES = 32
)(
    output logic        s_tready,
    input  logic        s_tvalid,
    input  logic        s_tlast,
    input  logic [63:0] s_tdata,
    input  logic [7:0]  s_tkeep,
    input  logic        s_tuser, // Used as an error input signal, valid on tlast

    output logic                       msg_valid,   // High for one clock to output a message
    output logic [15:0]                msg_length,  // Length of the message
    output logic [8*MAX_MSG_BYTES -1:0] msg_data,    // Data with the LSB on [0]
    output logic                       msg_error,   // Output if issue with the message

    input  logic clk,
    input  logic rst
);


    // local parameters
    localparam MSG_LENGTH_WIDTH = 2;
    localparam MSG_COUNT_WIDTH = 2;
    localparam MAX_STREAM_WIDTH = 1500;
    localparam MAX_MSG_BYTES_ALIGNED =  (((MAX_MSG_BYTES - 1) / 8) + 1) * 8;

    // wires/ registers
    logic s_tready_r;
    logic s_tlast_r;
    logic [7:0] s_tkeep_r;
    logic first;
    logic new_packet ;
    logic new_msg ;
    logic msg_error_r;
    logic s_tvalid_r;
    logic [15:0] msg_length_r;
    logic [MSG_COUNT_WIDTH*8 -1 : 0] msg_count_r;
    logic [MSG_COUNT_WIDTH*8 -1 : 0] msg_counter;
    logic [MSG_LENGTH_WIDTH*8 -1 : 0] accum_length;
    logic [MSG_LENGTH_WIDTH*8 -1 : 0] remaining_bytes;
    logic [MSG_LENGTH_WIDTH*8 -1 : 0] remaining_valid_bytes;
    logic [15 : 0] accum_length_r = 0;
    logic [15:0] data_counter;
    logic [8*MAX_MSG_BYTES_ALIGNED-1 : 0] msg_data_r;
    logic [8*MAX_MSG_BYTES_ALIGNED-1 : 0] mask;
    logic [8*MAX_MSG_BYTES_ALIGNED-1 : 0] msg_data_temp;
    //
    enum {IDLE, NEW_PKT, INCREMENT} state;

    //
    always@(posedge clk) begin
        if (rst) begin
            s_tready    <= 0;
            s_tlast_r   <= 0;
            s_tkeep_r   <= 0;
            s_tvalid_r  <= 0;
        end else begin
            s_tready    <= 1;
            s_tlast_r   <= s_tlast;
            s_tkeep_r   <= s_tkeep;
            s_tvalid_r  <= s_tvalid;
        end
    end

    always@(posedge clk) begin
        if (rst) begin
            first <= 0;
            msg_valid   <= 0;
            msg_length_r  <= 0;
            msg_length  <= 0;
            msg_data    <= 0;
            msg_error   <= 0;
            accum_length <= MSG_COUNT_WIDTH;
            remaining_bytes <= 0;
            remaining_valid_bytes <= 0;
            data_counter <= 0;
            msg_data_r   <= 0;
            msg_data_temp <= 0;
            mask         <= 0;
            new_packet   <= 0;
            new_msg      <= 0;
            msg_count_r  <= 0;
            msg_counter  <= 0;
            msg_error_r  <= 0;
            state        <= IDLE;
        end else begin
            msg_error <= msg_error_r | s_tuser;
            case (state)
                IDLE:
                    begin
                        if (!s_tvalid) begin
                            state           <= IDLE;
                            msg_data        <= 0;
                            msg_length_r    <= 0;
                            msg_length      <= 0;
                            msg_valid       <= 0;
                        end else begin
                            state           <= NEW_PKT;
                            new_packet      <= 1;
                            new_msg         <= 1;
                            msg_valid       <= 0;
                            msg_data        <= 0;
                            msg_data_r[data_counter*64 +: 64] <= s_tdata;
                            data_counter    <= data_counter +1;
                            msg_counter     <= msg_counter +1;
                            msg_count_r     <= s_tdata[MSG_COUNT_WIDTH*8 -1 : 0];
                            msg_length_r    <= s_tdata[MSG_COUNT_WIDTH*8  +: MSG_LENGTH_WIDTH*8];
                        end
                    end

                NEW_PKT:
                    begin
                        if ((msg_length_r) < 8 | (msg_length_r > MAX_MSG_BYTES)) begin
                                $fatal("Message length is out of range: 8 <= msg_length <= %d. Received message length = %d", MAX_MSG_BYTES, msg_length_r);
                                msg_error_r <= 1;
                        end
                        if (s_tvalid) begin
                            if (s_tlast_r) begin
                                $fatal("Unexpected tlast received. Min message length is 8 bytes, which need at least 2 valid transfers.");
                                msg_error_r <= 1;
                            end else begin
                                new_packet  <= 0;
                                new_msg     <= 0;
                                msg_valid   <= 0;
                                msg_data_r[data_counter*64 +: 64] <= s_tdata;
                                data_counter    <= data_counter +1;
                                accum_length  <= accum_length + msg_length_r + MSG_LENGTH_WIDTH; 
                                state <= INCREMENT;
                            end
                        end else begin
                            state <= NEW_PKT;
                        end
                    end

                INCREMENT:
                    begin

                        if ((msg_length_r) < 8 | (msg_length_r > MAX_MSG_BYTES)) begin
                                $fatal("Message length is out of range: 8 <= msg_length <= %d. Received message length = %d", MAX_MSG_BYTES, msg_length_r);
                                msg_error_r <= 1;
                        end

                        if (s_tvalid | s_tvalid_r) begin
                            //
                            if ((data_counter)*8 >= accum_length) begin
                                //
                                //Extract the valid data
                                //
                                mask = {8*MAX_MSG_BYTES_ALIGNED{1'b1}} >> (MAX_MSG_BYTES_ALIGNED - accum_length - remaining_bytes)*8 ;
                                msg_data_temp <= msg_data_r & mask;
                                if (msg_counter == 1) begin
                                    //remove 2 bytes of msg_count_r and 2 bytes of msg_length_r 
                                    msg_data = (msg_data_r & mask) >> 32;
                                end else begin
                                    //remove 2 bytes of msg_length_r 
                                    msg_data = (msg_data_r & mask) >> 16;
                                end
                                msg_length <= msg_length_r;
                                //
                                remaining_bytes <= data_counter*8 - accum_length;
                                if ((data_counter *8 - accum_length) == 0) begin
                                    //reaching the end of the transfer
                                    msg_data_r[63: 0] <= s_tdata;
                                    msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 64] <= 0;
                                    remaining_valid_bytes <= 0;
                                    //
                                    if (!s_tlast_r) begin
                                        //As the minimum msg_length_r is 8 bytes, we are sure that the last transfer (tlast =1) does not contain a new msg
                                        msg_length_r <= s_tdata[0 +: MSG_LENGTH_WIDTH*8];
                                        accum_length  <= s_tdata[0 +: MSG_LENGTH_WIDTH*8] + MSG_LENGTH_WIDTH;
                                    end
                                end else if ((data_counter *8 - accum_length) == 1) begin
                                    if (s_tkeep_r[7] == 1'b0) begin
                                        // no valid bytes remaining within the transfer
                                        msg_data_r[63: 0] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 64] <= 0;
                                        remaining_valid_bytes <= 0;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= s_tdata[0 +: MSG_LENGTH_WIDTH*8];
                                            accum_length  <= s_tdata[0 +: MSG_LENGTH_WIDTH*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else begin
                                        //collect the remaining valid 1 byte
                                        msg_data_r[7 : 0] <= msg_data_r[(data_counter*8 -1 + remaining_valid_bytes)*8 +: 8];
                                        msg_data_r[71: 8] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 72] <= 0;
                                        remaining_valid_bytes <= 1;
                                        //
                                        if (!s_tlast_r)begin 
                                            msg_length_r <= {s_tdata[7 : 0], msg_data_r[(data_counter*8 -1 + remaining_valid_bytes)*8 +: 8]};
                                            accum_length  <= {s_tdata[7 : 0], msg_data_r[(data_counter*8 -1 + remaining_valid_bytes)*8 +: 8]} -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end
                                end else if ((data_counter *8 - accum_length) == 2) begin
                                    if (s_tkeep_r[7:6] == 2'b00) begin
                                        // no valid bytes remaining within the transfer
                                        msg_data_r[63: 0] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 64] <= 0;
                                        remaining_valid_bytes <= 0;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= s_tdata[0 +: MSG_LENGTH_WIDTH*8];
                                            accum_length  <= s_tdata[0 +: MSG_LENGTH_WIDTH*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:6] == 2'b01) begin
                                        //collect the remaining valid 1 byte
                                        msg_data_r[7 : 0] <= msg_data_r[(data_counter*8 -2 + remaining_valid_bytes)*8 +: 8];
                                        msg_data_r[71: 8] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 72] <= 0;
                                        remaining_valid_bytes <= 1;
                                        //
                                        if (!s_tlast_r) begin 
                                            msg_length_r <= {s_tdata[7 : 0], msg_data_r[(data_counter*8 -2 + remaining_valid_bytes)*8 +: 8]};
                                            accum_length  <= {s_tdata[7 : 0], msg_data_r[(data_counter*8 -2 + remaining_valid_bytes)*8 +: 8]} -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:6] == 2'b11) begin
                                        //collect the remaining valid 2 bytes
                                        msg_data_r[15 : 0] <= msg_data_r[(data_counter*8 -2 + remaining_valid_bytes)*8 +: 2*8];
                                        msg_data_r[79: 16] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 80] <= 0;
                                        remaining_valid_bytes <= 2;
                                        //
                                        if (!s_tlast_r) begin 
                                            msg_length_r <= msg_data_r[(data_counter*8 -2 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -2 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end
                                end else if ((data_counter *8 - accum_length) == 3) begin
                                    if (s_tkeep_r[7:5] == 3'b000) begin
                                        // no valid bytes remaining within the transfer
                                        msg_data_r[63: 0] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 64] <= 0;
                                        remaining_valid_bytes <= 0;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= s_tdata[0 +: MSG_LENGTH_WIDTH*8];
                                            accum_length  <= s_tdata[0 +: MSG_LENGTH_WIDTH*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:5] == 3'b001) begin
                                        //collect the remaining valid 1 byte
                                        msg_data_r[7 : 0] <= msg_data_r[(data_counter*8 -3 + remaining_valid_bytes)*8 +: 8];
                                        msg_data_r[71: 8] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 72] <= 0;
                                        remaining_valid_bytes <= 1;
                                        //
                                        if (!s_tlast_r) begin 
                                            msg_length_r <= {s_tdata[7 : 0], msg_data_r[(data_counter*8 -3 + remaining_valid_bytes)*8 +: 8]};
                                            accum_length  <= {s_tdata[7 : 0], msg_data_r[(data_counter*8 -3 + remaining_valid_bytes)*8 +: 8]} -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:5] == 3'b011) begin
                                        //collect the remaining valid 2 bytes
                                        msg_data_r[15 : 0] <= msg_data_r[(data_counter*8 -3 + remaining_valid_bytes)*8 +: 2*8];
                                        msg_data_r[79: 16] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 80] <= 0;
                                        remaining_valid_bytes <= 2;
                                        //
                                        if (!s_tlast_r) begin 
                                            msg_length_r <= msg_data_r[(data_counter*8 -3 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -3 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:5] == 3'b111) begin
                                        //collect the remaining valid 3 bytes
                                        msg_data_r[23 : 0] <= msg_data_r[(data_counter*8 -3 + remaining_valid_bytes)*8 +: 3*8];
                                        msg_data_r[87: 24] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 88] <= 0;
                                        remaining_valid_bytes <= 3;
                                        if (!s_tlast_r) begin
                                            msg_length_r <= msg_data_r[(data_counter*8 -3 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -3 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end
                                end else if ((data_counter *8 - accum_length) == 4) begin
                                    if (s_tkeep_r[7:4] == 4'b0000) begin
                                        // no valid bytes remaining within the transfer
                                        msg_data_r[63: 0] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 64] <= 0;
                                        remaining_valid_bytes <= 0;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= s_tdata[0 +: MSG_LENGTH_WIDTH*8];        
                                            accum_length  <= s_tdata[0 +: MSG_LENGTH_WIDTH*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:4] == 4'b0001) begin
                                        //collect the remaining valid 1 byte
                                        msg_data_r[7 : 0] <= msg_data_r[(data_counter*8 -4 + remaining_valid_bytes)*8 +: 8];
                                        msg_data_r[71: 8] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 72] <= 0;
                                        remaining_valid_bytes <= 1;
                                        //
                                        if (!s_tlast_r) begin 
                                            msg_length_r <= {s_tdata[7 : 0], msg_data_r[(data_counter*8 -4 + remaining_valid_bytes)*8 +: 8]};
                                            accum_length  <= {s_tdata[7 : 0], msg_data_r[(data_counter*8 -4 + remaining_valid_bytes)*8 +: 8]} -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end
                                    if (s_tkeep_r[7:4] == 4'b0011) begin
                                        //collect the remaining valid 2 bytes
                                        msg_data_r[15 : 0] <= msg_data_r[(data_counter*8 -4 + remaining_valid_bytes)*8 +: 2*8];
                                        msg_data_r[79: 16] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 80] <= 0;
                                        remaining_valid_bytes <= 2;
                                        if (!s_tlast_r) begin 
                                            msg_length_r <= msg_data_r[(data_counter*8 -4 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -4 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:4] == 4'b0111) begin
                                        //collect the remaining valid 3 bytes
                                        msg_data_r[23 : 0] <= msg_data_r[(data_counter*8 -4 + remaining_valid_bytes)*8 +: 3*8];
                                        msg_data_r[87: 24] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 88] <= 0;
                                        remaining_valid_bytes <= 3;
                                        if (!s_tlast_r) begin 
                                            msg_length_r <= msg_data_r[(data_counter*8 -4 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -4 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:4] == 4'b1111) begin
                                        //collect the remaining valid 4 bytes
                                        msg_data_r[31 : 0] <= msg_data_r[(data_counter*8 -4 + remaining_valid_bytes)*8 +: 4*8];
                                        msg_data_r[95: 32] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 96] <= 0;
                                        remaining_valid_bytes <= 4;
                                        if (!s_tlast_r) begin
                                            msg_length_r <= msg_data_r[(data_counter*8 -4 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -4 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end
                                end else if ((data_counter *8 - accum_length) == 5) begin
                                    if (s_tkeep_r[7:3] == 5'b00000) begin
                                        // no valid bytes remaining within the transfer
                                        msg_data_r[63: 0] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 64] <= 0;
                                        remaining_valid_bytes <= 0;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= s_tdata[0 +: MSG_LENGTH_WIDTH*8];                                    
                                            accum_length  <= s_tdata[0 +: MSG_LENGTH_WIDTH*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:3] == 5'b00001) begin
                                        //collect the remaining valid 1 byte
                                        msg_data_r[7 : 0] <= msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 8];
                                        msg_data_r[71: 8] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 72] <= 0;
                                        remaining_valid_bytes <= 1;
                                        //
                                        if (!s_tlast_r) begin 
                                            msg_length_r <= {s_tdata[7 : 0], msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 8]};
                                            accum_length  <= {s_tdata[7 : 0], msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 8]} -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:3] == 5'b00011) begin
                                        //collect the remaining valid 2 bytes
                                        msg_data_r[15 : 0] <= msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 2*8];
                                        msg_data_r[79: 16] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 80] <= 0;
                                        remaining_valid_bytes <= 2;
                                        //
                                        if (!s_tlast_r) begin 
                                            msg_length_r <= msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:3] == 5'b00111) begin
                                        //collect the remaining valid 3 bytes
                                        msg_data_r[23 : 0] <= msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 3*8];
                                        msg_data_r[87: 24] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 88] <= 0;
                                        remaining_valid_bytes <= 3;
                                        //
                                        if (!s_tlast_r) begin 
                                            msg_length_r <= msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:3] == 5'b01111) begin
                                        //collect the remaining valid 4 bytes
                                        msg_data_r[31 : 0] <= msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 4*8];
                                        msg_data_r[95: 32] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 96] <= 0;
                                        remaining_valid_bytes <= 4;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:3] == 5'b11111) begin
                                        //collect the remaining valid 5 bytes
                                        msg_data_r[39 : 0] <= msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 5*8];
                                        msg_data_r[103: 40] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 104] <= 0;
                                        remaining_valid_bytes <= 5;
                                        //
                                        if (!s_tlast_r) begin 
                                            msg_length_r <= msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -5 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end
                                end else if ((data_counter *8 - accum_length) == 6) begin
                                    if (s_tkeep_r[7:2] == 6'b000000) begin
                                        // no valid bytes remaining within the transfer
                                        msg_data_r[63: 0] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 64] <= 0;
                                        remaining_valid_bytes <= 0;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= s_tdata[0 +: MSG_LENGTH_WIDTH*8];
                                            accum_length  <= s_tdata[0 +: MSG_LENGTH_WIDTH*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:2] == 6'b000001) begin
                                        //collect the remaining valid 1 byte
                                        msg_data_r[7 : 0] <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 8];
                                        msg_data_r[71: 8] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 72] <= 0;
                                        remaining_valid_bytes <= 1;
                                        //
                                        if (!s_tlast_r) begin 
                                            msg_length_r <= {s_tdata[7 : 0], msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 8]};                                    
                                            accum_length  <= {s_tdata[7 : 0], msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 8]} -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:2] == 6'b000011) begin
                                        //collect the remaining valid 2 bytes
                                        msg_data_r[15 : 0] <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 2*8];
                                        msg_data_r[79: 16] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 80] <= 0;
                                        remaining_valid_bytes <= 2;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:2] == 6'b000111) begin
                                        //collect the remaining valid 3 bytes
                                        msg_data_r[23 : 0] <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 3*8];
                                        msg_data_r[87: 24] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 88] <= 0;
                                        remaining_valid_bytes <= 3;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:2] == 6'b001111) begin
                                        //collect the remaining valid 4 bytes
                                        msg_data_r[31 : 0] <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 4*8];
                                        msg_data_r[95: 32] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 96] <= 0;
                                        remaining_valid_bytes <= 4;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:2] == 6'b011111) begin
                                        //collect the remaining valid 5 bytes
                                        msg_data_r[39 : 0] <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 5*8];
                                        msg_data_r[103: 40] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 104] <= 0;
                                        remaining_valid_bytes <= 5;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:2] == 6'b111111) begin
                                        //collect the remaining valid 6 bytes
                                        msg_data_r[47 : 0] <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 6*8];
                                        msg_data_r[111: 48] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 112] <= 0;
                                        remaining_valid_bytes <= 6;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -6 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end
                                end else if ((data_counter *8 - accum_length) == 7) begin
                                    if (s_tkeep_r[7:1] == 7'b0000000) begin
                                        // no valid bytes remaining within the transfer
                                        msg_data_r[63: 0] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 64] <= 0;
                                        remaining_valid_bytes <= 0;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= s_tdata[0 +: MSG_LENGTH_WIDTH*8];
                                            accum_length  <= s_tdata[0 +: MSG_LENGTH_WIDTH*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:1] == 7'b0000001) begin
                                        //collect the remaining valid 1 byte
                                        msg_data_r[7 : 0] <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 8];
                                        msg_data_r[71: 8] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 72] <= 0;
                                        remaining_valid_bytes <= 1;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= {s_tdata[7 : 0], msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 8]};
                                            accum_length  <= {s_tdata[7 : 0], msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 8]} -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:1] == 7'b0000011) begin
                                        //collect the remaining valid 2 bytes
                                        msg_data_r[15 : 0] <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 2*8];
                                        msg_data_r[79: 16] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 80] <= 0;
                                        remaining_valid_bytes <= 2;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:1] == 7'b0000111) begin
                                        //collect the remaining valid 3 bytes
                                        msg_data_r[23 : 0] <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 3*8];
                                        msg_data_r[87: 24] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 88] <= 0;
                                        remaining_valid_bytes <= 3;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:1] == 7'b0001111) begin
                                        //collect the remaining valid 4 bytes
                                        msg_data_r[31 : 0] <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 4*8];
                                        msg_data_r[95: 32] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 96] <= 0;
                                        remaining_valid_bytes <= 4;
                                        //
                                        if (!s_tlast_r) begin 
                                            msg_length_r <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:1] == 7'b0011111) begin
                                        //collect the remaining valid 5 bytes
                                        msg_data_r[39 : 0] <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 5*8];
                                        msg_data_r[103: 40] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 104] <= 0;
                                        remaining_valid_bytes <= 5;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:1] == 7'b0111111) begin
                                        //collect the remaining valid 6 bytes
                                        msg_data_r[47 : 0] <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 6*8];
                                        msg_data_r[111: 48] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 112] <= 0;
                                        remaining_valid_bytes <= 6;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end else if (s_tkeep_r[7:1] == 7'b1111111) begin
                                        //collect the remaining valid 7 bytes
                                        msg_data_r[55 : 0] <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 7*8];
                                        msg_data_r[119: 56] <= s_tdata;
                                        msg_data_r[8*MAX_MSG_BYTES_ALIGNED -1 : 120] <= 0;
                                        remaining_valid_bytes <= 7;
                                        //
                                        if (!s_tlast_r) begin
                                            msg_length_r <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 2*8];
                                            accum_length  <= msg_data_r[(data_counter*8 -7 + remaining_valid_bytes)*8 +: 2*8] -(data_counter*8 - accum_length) + MSG_LENGTH_WIDTH;
                                        end
                                    end
                                end
                                //
                                if (s_tlast_r) begin
                                    if (s_tvalid) begin
                                        // New packet
                                        state           <= NEW_PKT;
                                        new_packet      <= 1;
                                        new_msg         <= 1;
                                        msg_valid       <= 1;
                                        msg_count_r     <= s_tdata[MSG_COUNT_WIDTH*8 -1 : 0]; //CHECKME : what if the 2 bytes of the msg_count_r are distributed on 2 transfers?
                                        msg_length_r    <= s_tdata[MSG_COUNT_WIDTH*8  +: MSG_LENGTH_WIDTH*8];
                                        accum_length  <= MSG_COUNT_WIDTH;
                                        remaining_bytes <= 0;
                                        remaining_valid_bytes <= 0;
                                        data_counter    <= 1;
                                        if (msg_counter == msg_count_r) begin
                                            msg_counter <= 1;
                                        end else begin
                                            $fatal("Received tlast signal, while not all messages have been processed. MSG count = %d ; Msg counter = %d", msg_count_r, msg_counter);
                                        end
                                    end else begin
                                        state <= IDLE;
                                        msg_data_r      <= 0;
                                        new_packet      <= 0;
                                        new_msg         <= 0;
                                        msg_valid       <= 1;
                                        msg_counter     <= 0;
                                        msg_count_r     <= 0;
                                        data_counter    <= 0;
                                        accum_length <= MSG_COUNT_WIDTH;
                                        msg_length_r  <= 0;
                                        remaining_bytes <= 0;
                                        remaining_valid_bytes <= 0;
                                    end
                                end else begin
                                    state           <= INCREMENT;
                                    new_packet      <= 0;
                                    msg_counter     <= msg_counter +1;
                                    data_counter    <= 1;
                                    new_msg         <= 1;
                                    msg_valid       <= 1;
                                end
                            end else begin
                                state           <= INCREMENT;
                                new_packet      <= 0;
                                new_msg         <= 0;
                                msg_valid       <= 0;
                                data_counter    <= data_counter +1;
                                msg_data_r[(data_counter*8 + remaining_valid_bytes)*8 +: 64] <= s_tdata;
                            end
                        end else begin
                            if (!s_tlast_r) begin
                                state <= INCREMENT;
                            end else begin
                                state <= IDLE;
                                msg_data_r      <= 0;
                                msg_data        <= 0;
                                msg_length      <= 0;
                                new_packet      <= 0;
                                new_msg         <= 0;
                                msg_valid       <= 0;
                                msg_counter     <= 0;
                                msg_count_r     <= 0;
                                accum_length <= MSG_COUNT_WIDTH;
                                msg_length_r  <= 0;
                                data_counter    <= 0;
                                remaining_bytes <= 0;
                                remaining_valid_bytes <= 0;
                            end
                        end
                    end
            endcase
        end
    end
endmodule

/*
Sample inputs:

tvalid,tlast,       tdata       ,  tkeep    ,terror
1     ,  0  ,abcddcef_00080001  ,11111111   ,0
1     ,  1  ,00000000_630d658d  ,00001111   ,0
1     ,  0  ,045de506_000e0002  ,11111111   ,0
1     ,  0  ,03889560_84130858  ,11111111   ,0
1     ,  0  ,85468052_0008a5b0  ,11111111   ,0
1     ,  1  ,00000000_d845a30c  ,00001111   ,0
1     ,  0  ,62626262_00080008  ,11111111   ,0
1     ,  0  ,6868000c_62626262  ,11111111   ,0
1     ,  0  ,68686868_68686868  ,11111111   ,0
1     ,  0  ,70707070_000a6868  ,11111111   ,0
1     ,  0  ,000f7070_70707070  ,11111111   ,0
1     ,  0  ,7a7a7a7a_7a7a7a7a  ,11111111   ,0
1     ,  0  ,0e7a7a7a_7a7a7a7a  ,11111111   ,0
1     ,  0  ,4d4d4d4d_4d4d4d00  ,11111111   ,0
1     ,  0  ,114d4d4d_4d4d4d4d  ,11111111   ,0
1     ,  0  ,38383838_38383800  ,11111111   ,0
1     ,  0  ,38383838_38383838  ,11111111   ,0
1     ,  0  ,31313131_000b3838  ,11111111   ,0
1     ,  0  ,09313131_31313131  ,11111111   ,0
1     ,  0  ,5a5a5a5a_5a5a5a00  ,11111111   ,0
1     ,  1  ,00000000_00005a5a  ,00000011   ,0


+--------------------------------------------------------------------+
| MSG_COUNT | MSG_LENGTH |              MSG                          |
|-----------|------------|-------------------------------------------|
|    1      |     8      |                       630d658d_abcddcef   |
|-----------|------------|-------------------------------------------|
|           |    14      |         a5b0_03889560_84130858_045de506   |
|    2      |------------|-------------------------------------------|
|           |     8      |                       d845a30c_85468052   |
|-----------|------------|-------------------------------------------|
|    8      |     8      |                       62626262_62626262   |
|           |------------|-------------------------------------------|
|           |    12      |             6868_68686868_68686868_6868   |
|           |------------|-------------------------------------------|
|           |    10      |                  7070_70707070_70707070   |
|           |------------|-------------------------------------------|
|           |    15      |       7a7a7a_7a7a7a7a_7a7a7a7a_7a7a7a7a   |
|           |------------|-------------------------------------------|
|           |    14      |         4d4d4d_4d4d4d4d_4d4d4d4d_4d4d4d   |
|           |------------|-------------------------------------------|
|           |    17      |  3838_38383838_38383838_38383838_383838   |
|           |------------|-------------------------------------------|
|           |    11      |                313131_31313131_31313131   |
|           |------------|-------------------------------------------|
|           |     9      |                    5a5a_5a5a5a5a_5a5a5a   |
+--------------------------------------------------------------------+

*/
