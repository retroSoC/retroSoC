module axi4l2mem (
    input         ACLK,
    input         ARESETn,
    input  [31:0] AWADDR,
    input         AWVALID,
    output        AWREADY,
    input  [31:0] WDATA,
    input  [ 3:0] WSTRB,
    input         WVALID,
    output        WREADY,
    output [ 1:0] BRESP,
    output        BVALID,
    input         BREADY,
    input  [31:0] ARADDR,
    input         ARVALID,
    output        ARREADY,
    output [31:0] RDATA,
    output [ 1:0] RRESP,
    output        RVALID,
    input         RREADY,

    output        mem_valid,
    output        mem_instr,
    output [31:0] mem_addr,
    output [31:0] mem_wdata,
    output [ 3:0] mem_wstrb,
    input         mem_ready,
    input  [31:0] mem_rdata
);

  localparam [2:0] IDLE = 3'b000;
  localparam [2:0] READ_ADDR = 3'b001;
  localparam [2:0] READ_DATA = 3'b010;
  localparam [2:0] WRITE_ADDR = 3'b011;
  localparam [2:0] WRITE_DATA = 3'b100;
  localparam [2:0] WRITE_MEM = 3'b101;
  localparam [2:0] WRITE_RESP = 3'b110;

  reg [2:0] state, next_state;
  reg [31:0] raddr, waddr;
  reg [31:0] wdata;
  reg [ 3:0] wstrb;
  reg [31:0] rdata_reg;

  always @(posedge ACLK) begin
    if (!ARESETn) begin
      state <= IDLE;
    end else begin
      state <= next_state;
    end
  end

  always @(*) begin
    next_state = state;
    case (state)
      IDLE: begin
        if (ARVALID) begin
          next_state = READ_ADDR;
        end else if (AWVALID) begin
          next_state = WRITE_ADDR;
        end
      end

      READ_ADDR: begin
        if (mem_ready) begin
          next_state = READ_DATA;
        end
      end

      READ_DATA: begin
        if (RREADY) begin
          next_state = IDLE;
        end
      end

      WRITE_ADDR: begin
        if (WVALID) begin
          next_state = WRITE_DATA;
        end
      end

      WRITE_DATA: begin
        next_state = WRITE_MEM;
      end

      WRITE_MEM: begin
        if (mem_ready) begin
          next_state = WRITE_RESP;
        end
      end

      WRITE_RESP: begin
        if (BREADY) begin
          next_state = IDLE;
        end
      end

      default: next_state = IDLE;
    endcase
  end

  always @(posedge ACLK) begin
    if (!ARESETn) begin
      raddr     <= 32'b0;
      waddr     <= 32'b0;
      wdata     <= 32'b0;
      wstrb     <= 4'b0;
      rdata_reg <= 32'b0;
    end else begin
      if (state == IDLE && next_state == READ_ADDR) begin
        raddr <= ARADDR;
      end

      if (state == IDLE && next_state == WRITE_ADDR) begin
        waddr <= AWADDR;
      end

      if (state == WRITE_ADDR && WVALID) begin
        wdata <= WDATA;
        wstrb <= WSTRB;
      end

      if (state == READ_ADDR && mem_ready) begin
        rdata_reg <= mem_rdata;
      end
    end
  end

  assign ARREADY   = (state == IDLE && next_state == READ_ADDR);
  assign AWREADY   = (state == IDLE && next_state == WRITE_ADDR);
  assign WREADY    = (state == WRITE_ADDR && WVALID);
  assign BVALID    = (state == WRITE_RESP);
  assign BRESP     = 2'b00;
  assign RVALID    = (state == READ_DATA);
  assign RRESP     = 2'b00;
  assign RDATA     = rdata_reg;

  assign mem_valid = (state == READ_ADDR) || (state == WRITE_MEM);
  assign mem_instr = 1'b0;
  assign mem_addr  = (state == READ_ADDR) ? raddr : (state == WRITE_MEM) ? waddr : 32'b0;
  assign mem_wdata = wdata;
  assign mem_wstrb = (state == READ_ADDR) ? 4'b0000 : (state == WRITE_MEM) ? wstrb : 4'b0000;

endmodule
