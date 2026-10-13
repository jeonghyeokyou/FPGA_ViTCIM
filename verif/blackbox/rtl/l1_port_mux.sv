`timescale 1ns/1ps
// =============================================================================
//  l1_port_mux  -  L1 SRAM 입력 포트 선택 (조합논리)
//    기본 규칙 : i_pe_busy = 1 -> SRAM 입력(ceb/web/addr/din) <- PE, 0 -> NoC
//    예외      : i_pe_busy = 1 이라도 NoC 쪽 ceb = 0 (이미 출발한 접근)이면 그 클럭은 NoC 가 쓴다.
//  dout 은 선택과 무관하게 양쪽에 그대로 나간다.
//
//  왜 예외가 필요한가 (FINDING_busy_fall_before_l1_write.md)
//  ---------------------------------------------------------------------------
//  L1_FIFO_interface 는 pe_busy 로 "새" 요청을 조합논리로 즉시 막지만, 그 뒤의
//  noc_sram_controller 가 ceb/web/addr/din 을 레지스터로 한 번 더 잡는다. 그래서 pe_busy 가
//  올라간 바로 그 클럭에 컨트롤러 레지스터에 이미 들어간 접근이 최대 1개 남아 있을 수 있다
//  (burst LOAD 의 마지막 beat 가 L2 busy↓ + 2 클럭에 SRAM 에 쓰이는 것이 그 경우).
//  원래 mux 는 이 접근을 버렸다 -> busy↓ 직후 START 하면 마지막 입력 beat 유실.
//  pe_busy=1 이 된 뒤에는 L1_FIFO_interface 가 새 요청을 내지 않으므로 NoC ceb=0 은 이 "남은
//  1개" 뿐이고, PE 는 pe_busy 를 올린 뒤 GUARD(>=1) 클럭 동안 SRAM 에 접근하지 않으므로 겹치지 않는다.
//  o_pe_conflict : PE 와 NoC 가 같은 클럭에 접근해 PE 접근이 밀린 경우 (정상 동작에서는 항상 0, 검증용)
// =============================================================================
module l1_port_mux #(
    parameter ADDR_BW    = 11,
    parameter DATA_WIDTH = 512
)(
    input  wire                  i_pe_busy,
    // NoC side
    input  wire                  i_noc_ceb,
    input  wire                  i_noc_web,
    input  wire [ADDR_BW-1:0]    i_noc_addr,
    input  wire [DATA_WIDTH-1:0] i_noc_din,
    output wire [DATA_WIDTH-1:0] o_noc_dout,
    // PE side
    input  wire                  i_pe_ceb,
    input  wire                  i_pe_web,
    input  wire [ADDR_BW-1:0]    i_pe_addr,
    input  wire [DATA_WIDTH-1:0] i_pe_din,
    output wire [DATA_WIDTH-1:0] o_pe_dout,
    // SRAM side
    output wire                  o_sram_ceb,
    output wire                  o_sram_web,
    output wire [ADDR_BW-1:0]    o_sram_addr,
    output wire [DATA_WIDTH-1:0] o_sram_din,
    input  wire [DATA_WIDTH-1:0] i_sram_dout,
    // debug
    output wire                  o_pe_conflict
);
    // PE owns the port only when pe_busy AND the NoC has no access in flight
`ifdef BB_ORIG_MUX
    wire sel_pe = i_pe_busy;                 // original rule (reproduces FINDING_busy_fall_before_l1_write)
`else
    wire sel_pe = i_pe_busy && i_noc_ceb;
`endif

    assign o_sram_ceb  = sel_pe ? i_pe_ceb  : i_noc_ceb;
    assign o_sram_web  = sel_pe ? i_pe_web  : i_noc_web;
    assign o_sram_addr = sel_pe ? i_pe_addr : i_noc_addr;
    assign o_sram_din  = sel_pe ? i_pe_din  : i_noc_din;

    assign o_noc_dout  = i_sram_dout;
    assign o_pe_dout   = i_sram_dout;

    assign o_pe_conflict = i_pe_busy && !i_noc_ceb && !i_pe_ceb;
endmodule
