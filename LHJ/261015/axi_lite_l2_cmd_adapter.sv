`timescale 1ns/1ps
// 64-bit AXI4-Lite -> existing L2 command ready/valid.
// One AXI write transaction at a time; AW and W captured independently.
// OKAY means accepted into this adapter, NOT L2 execution complete.
// aresetn must be deasserted synchronously to aclk. All L2 signals share aclk.
module axi_lite_l2_cmd_adapter #(
    parameter bit CHECK_L2_OPCODE = 1'b1
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK",
       X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET aresetn" *)
    input wire aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST",
       X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR",
       X_INTERFACE_PARAMETER = "PROTOCOL AXI4LITE, DATA_WIDTH 64, ADDR_WIDTH 12, READ_WRITE_MODE READ_WRITE" *)
    input wire [11:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input wire [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input wire  s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire  s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input wire [63:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input wire [7:0] s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input wire  s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire  s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output logic [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output logic  s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input wire  s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input wire [11:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input wire [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input wire  s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire  s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output logic [63:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output logic [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output logic  s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input wire  s_axi_rready,
    output logic [63:0] o_command,
    output logic        o_command_valid,
    input  wire         i_command_ready,
    // Bit 0: ch1_in; 1: ch2_in; 2: ch1_wgt; 3: ch2_wgt.
    // Observations only: busy==0 does NOT prove all queued commands completed.
    input wire [3:0] i_channel_busy
);
    localparam [11:0] CMD_PUSH = 12'h000, STATUS = 12'h008,
                     ACCEPTED = 12'h010, FORWARDED = 12'h018,
                     CHANNEL_BUSY = 12'h020, ERRORS = 12'h028,
                     VERSION = 12'h030;
    localparam [1:0] OKAY = 2'b00, SLVERR = 2'b10;
    logic aw_saved, w_saved;
    logic [11:0] awaddr_q;
    logic [63:0] wdata_q;
    logic [7:0] wstrb_q;
    logic [63:0] accepted_count, forwarded_count;
    // Sticky bits: 0=write address, 1=partial command, 2=opcode zero,
    //              3=write to read-only register, 4=read address/write-only read.
    logic [4:0] error_status;
    logic [4:0] write_errors;
    logic [63:0] read_value;
    logic read_error;
    wire cmd_fire = o_command_valid && i_command_ready;
    wire read_fire = s_axi_arvalid && s_axi_arready;
    wire null_write = (wstrb_q == 8'h00);
    wire push_request = !null_write && awaddr_q == CMD_PUSH && write_errors == 0;
    // Registered holding slots, no AXI input -> AXI output combinational path.
    assign s_axi_awready = aresetn && !aw_saved && !s_axi_bvalid;
    assign s_axi_wready  = aresetn && !w_saved  && !s_axi_bvalid;
    assign s_axi_arready = aresetn && !s_axi_rvalid;
    // A waiting command may be replaced only on its actual L2 handshake.
    wire write_commit = aw_saved && w_saved && !s_axi_bvalid &&
                        (!push_request || !o_command_valid || i_command_ready);

    // Current L2-specific guard, kept separate from the transport machinery.
    // It is deliberately NOT a complete decoder/address/mode validator.
    always_comb begin
        write_errors = '0;
        if (!null_write) begin
            case (awaddr_q)
                CMD_PUSH: begin
                    if (wstrb_q != 8'hff) write_errors[1] = 1'b1;
                    if (CHECK_L2_OPCODE && wdata_q[62:60] == 3'b000)
                        write_errors[2] = 1'b1;
                end
                ERRORS: begin end  // W1C, low byte strobe controls the 5 bits.
                STATUS, ACCEPTED, FORWARDED, CHANNEL_BUSY, VERSION:
                    write_errors[3] = 1'b1;
                default: write_errors[0] = 1'b1;
            endcase
        end
    end

    // Read snapshot is captured on AR handshake, then held through R stalls.
    always_comb begin
        read_value = '0;
        read_error = 1'b0;
        case (s_axi_araddr)
            STATUS: begin
                read_value[0] = o_command_valid;
                read_value[1] = i_command_ready;
                read_value[2] = !o_command_valid;
                read_value[3] = aw_saved;
                read_value[4] = w_saved;
                read_value[5] = s_axi_bvalid;
                read_value[6] = |error_status;
            end
            ACCEPTED: read_value = accepted_count;
            FORWARDED: read_value = forwarded_count;
            CHANNEL_BUSY: read_value[3:0] = i_channel_busy;
            ERRORS: read_value[4:0] = error_status;
            VERSION: begin
                read_value[31:0] = 32'h0001_0000;
                read_value[32] = CHECK_L2_OPCODE;
            end
            default: read_error = 1'b1;
        endcase
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            aw_saved <= 1'b0; w_saved <= 1'b0;
            awaddr_q <= '0; wdata_q <= '0; wstrb_q <= '0;
            s_axi_bvalid <= 1'b0; s_axi_bresp <= OKAY;
            s_axi_rvalid <= 1'b0; s_axi_rresp <= OKAY; s_axi_rdata <= '0;
            o_command_valid <= 1'b0; o_command <= '0;
            accepted_count <= '0; forwarded_count <= '0;
            error_status <= '0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_saved <= 1'b1; awaddr_q <= s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_saved <= 1'b1; wdata_q <= s_axi_wdata; wstrb_q <= s_axi_wstrb;
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
            if (cmd_fire) begin
                o_command_valid <= 1'b0;
                forwarded_count <= forwarded_count + 64'd1;
            end
            if (write_commit) begin
                aw_saved <= 1'b0; w_saved <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= (write_errors != 0) ? SLVERR : OKAY;
                if (push_request) begin
                    o_command <= wdata_q;
                    o_command_valid <= 1'b1;
                    accepted_count <= accepted_count + 64'd1;
                end
                if (!null_write && awaddr_q == ERRORS && wstrb_q[0])
                    error_status <= error_status & ~wdata_q[4:0];
                else
                    error_status <= error_status | write_errors;
            end
            if (read_fire) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= read_error ? SLVERR : OKAY;
                s_axi_rdata <= read_value;
            end
            // New error wins over a simultaneous W1C clear.
            if (read_fire && read_error) error_status[4] <= 1'b1;
        end
    end
    wire unused_prot = &{1'b0, s_axi_awprot, s_axi_arprot};
    // AWPROT/ARPROT intentionally ignored: no privilege/security policy here.
    // Access control, if needed, belongs in the system interconnect/firewall.
endmodule
