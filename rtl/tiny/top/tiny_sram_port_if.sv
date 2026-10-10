// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// One word operation, byte strobes, one ordered response per accepted request.
// Local I/D retain their address through the response handshake (bank routing)
// and have one operation outstanding. A fixed-group external client may have
// two operations outstanding, including a reserved macro read return. It may
// advance its request address after acceptance; responses remain in order.
interface tiny_sram_port_if;
  logic req_valid, req_ready;
  logic [31:0] addr, wdata;
  logic       write;
  logic [3:0] wstrb;
  logic rsp_valid, rsp_ready;
  logic [31:0] rdata;

  modport master(
      output req_valid, addr, wdata, write, wstrb, rsp_ready,
      input req_ready, rsp_valid, rdata
  );
  modport slave(
      input req_valid, addr, wdata, write, wstrb, rsp_ready,
      output req_ready, rsp_valid, rdata
  );
endinterface
