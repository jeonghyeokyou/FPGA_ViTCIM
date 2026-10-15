`timescale 1ns/1ps
// Streaming full-word-only AXI4 -> L2 ch0. No burst-sized storage or RMW.
// 2-entry (DATA_WIDTH-bit data + LAST) queue; registered occupancy drives WREADY.
// Aligned full-word INCR 1..256, FIXED single; every WSTRB bit must be 1.
// Unsupported address requests are drained/rejected without L2 access.
// Bad WSTRB/WLAST on accepted writes: never forward offending beat; drain
// remaining AXI beats, SLVERR, latch fault until shared bridge+L2 reset.
// Accepted prefix can already be committed; no transaction rollback.
// Faulted subsequent requests return SLVERR without starting new L2 work.
// Master must still supply AWLEN+1 beats. No missing-beat/backend timeout.
// Upper address decode belongs to SmartConnect; size-aligned window required.
module axi4_l2_data_adapter #(
    parameter integer DATA_WIDTH     = 64, // supported configurations: 64,128
    parameter integer ADDR_WIDTH     = 40,
    parameter integer ID_WIDTH       = 16,
    parameter integer CH0_ADDR_WIDTH = 15      // L2 ch0 word 주소 폭 (top 에서 계산해 넘김)
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK", X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET aresetn" *)
    input  wire                      aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST", X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire                      aresetn,

    // ---------------- AXI4 slave ----------------
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWID" *)
    (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4, READ_WRITE_MODE READ_WRITE, MAX_BURST_LENGTH 256, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    input  wire [ID_WIDTH-1:0]       s_axi_awid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    input  wire [ADDR_WIDTH-1:0]     s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWLEN" *)
    input  wire [7:0]                s_axi_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWSIZE" *)
    input  wire [2:0]                s_axi_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWBURST" *)
    input  wire [1:0]                s_axi_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWLOCK" *)
    input  wire                      s_axi_awlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWCACHE" *)
    input  wire [3:0]                s_axi_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  wire [2:0]                s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWQOS" *)
    input  wire [3:0]                s_axi_awqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire                      s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire                      s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [DATA_WIDTH-1:0]               s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [DATA_WIDTH/8-1:0]   s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WLAST" *)
    input  wire                      s_axi_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire                      s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire                      s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BID" *)
    output wire [ID_WIDTH-1:0]       s_axi_bid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]                s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output wire                      s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire                      s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARID" *)
    input  wire [ID_WIDTH-1:0]       s_axi_arid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [ADDR_WIDTH-1:0]     s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARLEN" *)
    input  wire [7:0]                s_axi_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARSIZE" *)
    input  wire [2:0]                s_axi_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARBURST" *)
    input  wire [1:0]                s_axi_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARLOCK" *)
    input  wire                      s_axi_arlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARCACHE" *)
    input  wire [3:0]                s_axi_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  wire [2:0]                s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARQOS" *)
    input  wire [3:0]                s_axi_arqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire                      s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire                      s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RID" *)
    output wire [ID_WIDTH-1:0]       s_axi_rid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output wire [DATA_WIDTH-1:0]               s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]                s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RLAST" *)
    output wire                      s_axi_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output wire                      s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire                      s_axi_rready,

    // ---------------- L2 channel 0 ----------------
    output wire [CH0_ADDR_WIDTH-1:0] ch_awaddr,
    output wire [7:0]                ch_awlen,
    output wire                      ch_awvalid,
    input  wire                      ch_awready,
    output wire [DATA_WIDTH-1:0]               ch_wdata,
    output wire                      ch_wlast,
    output wire                      ch_wvalid,
    input  wire                      ch_wready,
    input  wire                      ch_bvalid,
    output wire                      ch_bready,
    output wire [CH0_ADDR_WIDTH-1:0] ch_araddr,
    output wire [7:0]                ch_arlen,
    output wire                      ch_arvalid,
    input  wire                      ch_arready,
    input  wire [DATA_WIDTH-1:0]               ch_rdata,
    input  wire                      ch_rlast,
    input  wire                      ch_rvalid,
    output wire                      ch_rready
);

    localparam integer STRB_WIDTH=DATA_WIDTH/8;
    localparam integer BYTE_SHIFT=$clog2(STRB_WIDTH);
    localparam integer OFS_BITS=CH0_ADDR_WIDTH+BYTE_SHIFT;
    generate
        if(DATA_WIDTH!=64 && DATA_WIDTH!=128) begin : g_bad_width
            initial $fatal(1,"DATA_WIDTH must be 64 or 128 for this release");
        end
        if(OFS_BITS<12 || OFS_BITS>ADDR_WIDTH) begin : g_bad_addr
            initial $fatal(1,"Address window must fit ADDR_WIDTH and be >=4KiB");
        end
    endgenerate
    localparam [OFS_BITS:0] MEM_BYTES={1'b1,{OFS_BITS{1'b0}}};
    typedef enum logic [2:0] {IDLE,WR,WB,WDRAIN,WERR,RA,RD,RERR} state_t;
    state_t st;
    reg prefer_read,fault;
    reg [ID_WIDTH-1:0] id;
    reg [7:0] len,cnt,backend_len;
    reg [CH0_ADDR_WIDTH-1:0] addr;
    reg aw_sent,write_open,received_last,sent_last;
    reg [DATA_WIDTH:0] q [0:1];
    reg wr_ptr,rd_ptr;
    reg [1:0] used;
    wire last_cnt=cnt==len;
    wire input_hs=s_axi_wvalid && s_axi_wready;
    wire input_bad=s_axi_wstrb!={STRB_WIDTH{1'b1}} || s_axi_wlast!=last_cnt;
    wire push=st==WR && input_hs && !input_bad;
    wire pop=ch_wvalid && ch_wready;
    function automatic logic req_ok(input [ADDR_WIDTH-1:0] a,input [7:0] l,
                                   input [2:0] sz,input [1:0] bu,input lk);
        logic [OFS_BITS:0] last_ofs;
        logic [16:0] page_last;
        begin
            last_ofs={1'b0,a[OFS_BITS-1:0]}+({{(OFS_BITS-7){1'b0}},l}<<BYTE_SHIFT);
            page_last={5'b0,a[11:0]}+(17'(l)<<BYTE_SHIFT);
            req_ok=a[BYTE_SHIFT-1:0]==0 && sz==3'(BYTE_SHIFT) && !lk &&
                   (bu==1 || (bu==0 && l==0)) && last_ofs<MEM_BYTES && page_last<4096;
        end
    endfunction
    assign s_axi_awready=st==IDLE && !prefer_read && aresetn;
    assign s_axi_arready=st==IDLE && prefer_read && aresetn;
    assign s_axi_wready=(st==WR && !received_last && used<2) || st==WDRAIN;
    assign s_axi_bid=id;
    assign s_axi_bvalid=(st==WB && ch_bvalid) || st==WERR;
    assign s_axi_bresp=st==WERR ? 2'b10 : 2'b00;
    assign s_axi_rid=id;
    assign s_axi_rvalid=(st==RD && ch_rvalid) || st==RERR;
    assign s_axi_rdata=st==RD ? ch_rdata : {DATA_WIDTH{1'b0}};
    assign s_axi_rlast=last_cnt;
    assign s_axi_rresp=st==RERR ? 2'b10 : ((ch_rlast!=last_cnt) ? 2'b10 : 2'b00);
    assign ch_awaddr=addr;
    assign ch_awlen=backend_len;
    assign ch_awvalid=write_open && !aw_sent;
    assign ch_wdata=q[rd_ptr][DATA_WIDTH-1:0];
    assign ch_wlast=q[rd_ptr][DATA_WIDTH];
    assign ch_wvalid=write_open && used!=0;
    assign ch_bready=st==WB && s_axi_bready;
    assign ch_araddr=addr;
    assign ch_arlen=backend_len;
    assign ch_arvalid=st==RA;
    assign ch_rready=st==RD && s_axi_rready;
    // Payload has no reset; used/pointers invalidate stale entries on reset.
    // Keep its write process separate from asynchronously reset control flops.
    always @(posedge aclk) begin
        if(aresetn && push)
            q[wr_ptr] <= {last_cnt,s_axi_wdata};
    end

    always @(posedge aclk or negedge aresetn) begin
        if(!aresetn) begin
            st<=IDLE;prefer_read<=0;fault<=0;id<=0;len<=0;cnt<=0;addr<=0;backend_len<=0;
            aw_sent<=0;write_open<=0;received_last<=0;sent_last<=0;
            wr_ptr<=0;rd_ptr<=0;used<=0;
        end else begin
            if(push) wr_ptr<=!wr_ptr;
            if(pop) begin rd_ptr<=!rd_ptr;if(ch_wlast) sent_last<=1;end
            case({push,pop}) 2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:;endcase
            if(ch_awvalid && ch_awready) aw_sent<=1;
            case(st)
                IDLE: begin
                    prefer_read<=!prefer_read;
                    cnt<=0;
                    if(s_axi_awvalid && s_axi_awready) begin
                        id<=s_axi_awid;len<=s_axi_awlen;
                        if(!fault && req_ok(s_axi_awaddr,s_axi_awlen,s_axi_awsize,s_axi_awburst,s_axi_awlock)) begin
                            addr<=s_axi_awaddr[OFS_BITS-1:BYTE_SHIFT];backend_len<=s_axi_awlen;
                            aw_sent<=0;write_open<=1;received_last<=0;sent_last<=0;st<=WR;
                        end else st<=WDRAIN;
                    end else if(s_axi_arvalid && s_axi_arready) begin
                        id<=s_axi_arid;len<=s_axi_arlen;
                        if(!fault && req_ok(s_axi_araddr,s_axi_arlen,s_axi_arsize,s_axi_arburst,s_axi_arlock)) begin
                            addr<=s_axi_araddr[OFS_BITS-1:BYTE_SHIFT];backend_len<=s_axi_arlen;st<=RA;
                        end else st<=RERR;
                    end
                end
                WR: begin
                    if(input_hs) begin
                        if(last_cnt) received_last<=1;else cnt<=cnt+1'b1;
                        if(input_bad) begin
                            fault<=1;
                            if(last_cnt) st<=WERR;else st<=WDRAIN;
                        end
                    end
                    if((aw_sent || (ch_awvalid && ch_awready)) &&
                       (sent_last || (pop && ch_wlast))) st<=WB;
                end
                WB: if(s_axi_bvalid && s_axi_bready) begin write_open<=0;st<=IDLE;end
                WDRAIN: if(input_hs) begin
                    if(last_cnt) st<=WERR;else cnt<=cnt+1'b1;
                end
                WERR: if(s_axi_bready) st<=IDLE;
                RA: if(ch_arvalid && ch_arready) st<=RD;
                RD: if(s_axi_rvalid && s_axi_rready) begin
                    if(last_cnt) st<=IDLE;else cnt<=cnt+1'b1;
                end
                RERR: if(s_axi_rready) begin
                    if(last_cnt) st<=IDLE;else cnt<=cnt+1'b1;
                end
                default: st<=IDLE;
            endcase
        end
    end
endmodule
