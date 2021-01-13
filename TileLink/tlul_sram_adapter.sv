/**
 * Tile-Link UL adapter for SRAM-like devices
 *
 * - Intentionally omitted BaseAddr in case of multiple memory maps are used in a SoC,
 *   it means that aliasing can happen if target device size in TL-UL crossbar is bigger
 *   than SRAM size
 */
module tlul_sram_adapter #(
  parameter int SramAw      = 12,
  parameter int SramDw      = 32, // Must be multiple of the TL width
  parameter int Outstanding = 1,  // Only one request is accepted
  parameter bit ByteAccess  = 1,  // 1: true, 0: false

) (
  input   clock,
  input   reset,

  // TL-UL interface
  input   tlul_pkg::tl_h2d_t  tl_d_c_a,
  output  tlul_pkg::tl_d2h_t  tl_d_c_d,

  // SRAM interface
  output logic              req_o,
  input                     gnt_i,
  output logic              we_o,
  output logic [SramAw-1:0] addr_o,
  output logic [SramDw-1:0] wdata_o,
  output logic [SramDw-1:0] wmask_o,
  input        [SramDw-1:0] rdata_i,
  input                     rvalid_i,
//  input        [1:0]        rerror_i // 2 bit error [1]: Uncorrectable, [0]: Correctable
);

  import tlul_pkg::*;

  localparam int SramByte = SramDw/8;
  localparam int DataBitWidth = tlul_pkg::vbits(SramByte);
  localparam int WidthMult = SramDw / tlul_pkg::TL_DW;
  localparam int WoffsetWidth = (SramByte == tlul_pkg::TL_DBW) ? 1 :
                                DataBitWidth - tlul_pkg::vbits(tlul_pkg::TL_DBW);

  typedef struct packed {
    logic [tlul_pkg::TL_DBW-1:0] mask ; // Byte mask within the TL-UL word
    logic [WoffsetWidth-1:0]    woffset ; // Offset of the TL-UL word within the SRAM word
  } sram_req_t ;

  typedef enum logic [1:0] {
    OpWrite,
    OpRead,
    OpUnknown
  } req_op_e ;

  typedef struct packed {
    req_op_e                    op ;
    logic                       error ;
    logic [tlul_pkg::TL_SZW-1:0] size ;
    logic [tlul_pkg::TL_AIW-1:0] source ;
  } req_t ;

  typedef struct packed {
    logic [SramDw-1:0] data ;
 //   logic              error ;
  } rsp_t ;

  localparam int SramReqFifoWidth = $bits(sram_req_t) ;
  localparam int ReqFifoWidth = $bits(req_t) ;
  localparam int RspFifoWidth = $bits(rsp_t) ;

  // FIFO signal in case OutStand is greater than 1
  // If request is latched, {write, source} is pushed to req fifo.
  // Req fifo is popped when D channel is acknowledged (v & r)
  // D channel valid is asserted if it is write request or rsp fifo not empty if read.
  logic reqfifo_wvalid, reqfifo_wready;
  logic reqfifo_rvalid, reqfifo_rready;
  req_t reqfifo_wdata,  reqfifo_rdata;

  logic sramreqfifo_wvalid, sramreqfifo_wready;
  logic sramreqfifo_rready;
  sram_req_t sramreqfifo_wdata, sramreqfifo_rdata;

  logic rspfifo_wvalid, rspfifo_wready;
  logic rspfifo_rvalid, rspfifo_rready;
  rsp_t rspfifo_wdata,  rspfifo_rdata;

  logic error_internal; // Internal protocol error checker
  logic wr_attr_error;
  logic wr_vld_error;
  logic rd_vld_error;
 // logic tlul_error;     // Error from `tlul_err` module

  logic a_ack, d_ack, sram_ack;
  assign a_ack    = tl_d_c_a.a_valid & tl_d_c_d.a_ready ;
  assign d_ack    = tl_d_c_d.d_valid & tl_d_c_a.d_ready ;
  assign sram_ack = req_o        & gnt_i ;

  // Valid handling
  logic d_valid, d_error;
  always_comb begin
    d_valid = 1'b0;

    if (reqfifo_rvalid) begin
      if (reqfifo_rdata.error) begin
        // Return error response. Assume no request went out to SRAM
        d_valid = 1'b1;
      end else if (reqfifo_rdata.op == OpRead) begin
        d_valid = rspfifo_rvalid;
      end else begin
        // Write without error
        d_valid = 1'b1;
      end
    end else begin
      d_valid = 1'b0;
    end
  end

  always_comb begin
    d_error = 1'b0;

    if (reqfifo_rvalid) begin
      if (reqfifo_rdata.op == OpRead) begin
        d_error = rspfifo_rdata.error | reqfifo_rdata.error;
      end else begin
        d_error = reqfifo_rdata.error;
      end
    end else begin
      d_error = 1'b0;
    end
  end

  assign tl_d_c_d = '{
      d_valid  : d_valid ,
      d_opcode : (d_valid && reqfifo_rdata.op != OpRead) ? AccessAck : AccessAckData,
      d_param  : '0,
      d_size   : (d_valid) ? reqfifo_rdata.size : '0,
      d_source : (d_valid) ? reqfifo_rdata.source : '0,
      d_sink   : 1'b0,
      d_data   : (d_valid && rspfifo_rvalid && reqfifo_rdata.op == OpRead)
                 ? rspfifo_rdata.data : '0,
      d_user   : '0,
      d_error  : d_valid && d_error,

      a_ready  : (gnt_i | error_internal) & reqfifo_wready & sramreqfifo_wready
  };

  // a_ready depends on the FIFO full condition and grant from SRAM (or SRAM arbiter)
  // assemble response, including read response, write response, and error for unsupported stuff

  // Output to SRAM:
  //    Generate request only when no internal error occurs. If error occurs, the request should be
  //    dropped and returned error response to the host. So, error to be pushed to reqfifo.
  //    In this case, it is assumed the request is granted (may cause ordering issue later?)
  assign req_o    = tl_d_c_a.a_valid & reqfifo_wready & ~error_internal;
  assign we_o     = tl_d_c_a.a_valid & logic'(tl_d_c_a.a_opcode inside {PutFullData, PutPartialData});
  assign addr_o   = (tl_d_c_a.a_valid) ? tl_d_c_a.a_address[DataBitWidth+:SramAw] : '0;

  // Support SRAMs wider than the TL-UL word width by mapping the parts of the
  // TL-UL address which are more fine-granular than the SRAM width to the
  // SRAM write mask.
  logic [WoffsetWidth-1:0] woffset;
  if (tlul_pkg::TL_DW != SramDw) begin : gen_wordwidthadapt
    assign woffset = tl_d_c_a.a_address[DataBitWidth-1:tlul_pkg::vbits(tlul_pkg::TL_DBW)];
  end else begin : gen_no_wordwidthadapt
    assign woffset = '0;
  end

  // Convert byte mask to SRAM bit mask for writes, and only forward valid data
  logic [WidthMult-1:0][tlul_pkg::TL_DW-1:0] wmask_int;
  logic [WidthMult-1:0][tlul_pkg::TL_DW-1:0] wdata_int;

  always_comb begin
    wmask_int = '0;
    wdata_int = '0;

    if (tl_d_c_a.a_valid) begin
      for (int i = 0 ; i < tlul_pkg::TL_DW/8 ; i++) begin
        wmask_int[woffset][8*i +: 8] = {8{tl_d_c_a.a_mask[i]}};
        wdata_int[woffset][8*i +: 8] = (tl_d_c_a.a_mask[i] && we_o) ? tl_d_c_a.a_data[8*i+:8] : '0;
      end
    end
  end

  assign wmask_o = wmask_int;
  assign wdata_o = wdata_int;

  // Begin: Request Error Detection

  // wr_attr_error: Check if the request size,mask are permitted.
  //    Basic check of size, mask, addr align is done in tlul_err module.
  //    Here it checks any partial write if ByteAccess isn't allowed.
  assign wr_attr_error = (tl_d_c_a.a_opcode == PutFullData || tl_d_c_a.a_opcode == PutPartialData) ?
                         (ByteAccess == 0) ? (tl_d_c_a.a_mask != '1 || tl_d_c_a.a_size != 2'h2) : 1'b0 :
                         1'b0;

//  if (ErrOnWrite == 1) begin : gen_no_writes
//    assign wr_vld_error = tl_d_c_a.a_opcode != Get;
//  end else begin : gen_writes_allowed
    assign wr_vld_error = 1'b0;
//  end

//  if (ErrOnRead == 1) begin: gen_no_reads
//    assign rd_vld_error = tl_d_c_a.a_opcode == Get;
//  end else begin : gen_reads_allowed
    assign rd_vld_error = 1'b0;
//  end

 /* tlul_err u_err (
    .clock,
    .reset,
    .tl_d_c_a,
    .err_o (tlul_error)
  );*/

  assign error_internal = wr_attr_error | wr_vld_error | rd_vld_error; //| tlul_error;
  // End: Request Error Detection

  assign reqfifo_wvalid = a_ack ; // Push to FIFO only when granted
  assign reqfifo_wdata  = '{
    op:     (tl_d_c_a.a_opcode != Get) ? OpWrite : OpRead, // To return AccessAck for opcode error
    error:  error_internal,
    size:   tl_d_c_a.a_size,
    source: tl_d_c_a.a_source
  }; // Store the request only. Doesn't have to store data
  assign reqfifo_rready = d_ack ;

  // push together with ReqFIFO, pop upon returning read
  assign sramreqfifo_wdata = '{
    mask    : tl_d_c_a.a_mask,
    woffset : woffset
  };
  assign sramreqfifo_wvalid = sram_ack & ~we_o;
  assign sramreqfifo_rready = rspfifo_wvalid;

  assign rspfifo_wvalid = rvalid_i & reqfifo_rvalid;

  // Make sure only requested bytes are forwarded
  logic [WidthMult-1:0][tlul_pkg::TL_DW-1:0] rdata;
  logic [WidthMult-1:0][tlul_pkg::TL_DW-1:0] rmask;
  //logic [SramDw-1:0] rmask;
  logic [tlul_pkg::TL_DW-1:0] rdata_tlword;

  always_comb begin
    rmask = '0;
    for (int i = 0 ; i < tlul_pkg::TL_DW/8 ; i++) begin
      rmask[sramreqfifo_rdata.woffset][8*i +: 8] = {8{sramreqfifo_rdata.mask[i]}};
    end
  end

  assign rdata = rdata_i & rmask;
  assign rdata_tlword = rdata[sramreqfifo_rdata.woffset];

  assign rspfifo_wdata  = '{
    data : rdata_tlword
//    error: rerror_i[1] // Only care for Uncorrectable error
  };
  assign rspfifo_rready = (reqfifo_rdata.op == OpRead & ~reqfifo_rdata.error)
                        ? reqfifo_rready : 1'b0 ;

  // This module only cares about uncorrectable errors.
//  logic unused_rerror;
//  assign unused_rerror = rerror_i[0];

  // FIFO instance: REQ, RSP

  // ReqFIFO is to store the Access type to match to the Response data.
  //    For instance, SRAM accepts the write request but doesn't return the
  //    acknowledge. In this case, it may be hard to determine when the D
  //    response for the write data should send out if reads/writes are
  //    interleaved. So, to make it in-order (even TL-UL allows out-of-order
  //    responses), storing the request is necessary. And if the read entry
  //    is write op, it is safe to return the response right away. If it is
  //    read reqeust, then D response is waiting until read data arrives.

  // Notes:
  // The oustanding+1 allows the reqfifo to absorb back to back transactions
  // without any wait states.  Alternatively, the depth can be kept as
  // oustanding as long as the outgoing ready is qualified with the acceptance
  // of the response in the same cycle.  Doing so however creates a path from
  // ready_i to ready_o, which may not be desireable.
  fifo_sync #(
    .Width   (ReqFifoWidth),
    .Pass    (1'b0),
    .Depth   (Outstanding)
  ) u_reqfifo (
    .clock,
    .reset,
    .clr_i   (1'b0),
    .wvalid_i(reqfifo_wvalid),
    .wready_o(reqfifo_wready),
    .wdata_i (reqfifo_wdata),
    .depth_o (),
    .rvalid_o(reqfifo_rvalid),
    .rready_i(reqfifo_rready),
    .rdata_o (reqfifo_rdata)
  );

  // sramreqfifo:
  //    While the ReqFIFO holds the request until it is sent back via TL-UL, the
  //    sramreqfifo only needs to hold the mask and word offset until the read
  //    data returns from memory.
  fifo_sync #(
    .Width   (SramReqFifoWidth),
    .Pass    (1'b0),
    .Depth   (Outstanding)
  ) u_sramreqfifo (
    .clock,
    .reset,
    .clr_i   (1'b0),
    .wvalid_i(sramreqfifo_wvalid),
    .wready_o(sramreqfifo_wready),
    .wdata_i (sramreqfifo_wdata),
    .depth_o (),
    .rvalid_o(),
    .rready_i(sramreqfifo_rready),
    .rdata_o (sramreqfifo_rdata)
  );

  // Rationale having #Outstanding depth in response FIFO.
  //    In normal case, if the host or the crossbar accepts the response data,
  //    response FIFO isn't needed. But if in any case it has a chance to be
  //    back pressured, the response FIFO should store the returned data not to
  //    lose the data from the SRAM interface. Remember, SRAM interface doesn't
  //    have back-pressure signal such as read_ready.
  fifo_sync #(
    .Width   (RspFifoWidth),
    .Pass    (1'b1),
    .Depth   (Outstanding)
  ) u_rspfifo (
    .clock,
    .reset,
    .clr_i   (1'b0),
    .wvalid_i(rspfifo_wvalid),
    .wready_o(rspfifo_wready),
    .wdata_i (rspfifo_wdata),
    .depth_o (),
    .rvalid_o(rspfifo_rvalid),
    .rready_i(rspfifo_rready),
    .rdata_o (rspfifo_rdata)
  );

endmodule