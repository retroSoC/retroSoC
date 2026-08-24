// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
// You can use this software according to the terms and conditions of Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

// Icarus compatibility models for UDPs referenced by the locked GF180 cells.
// The upstream functional models instantiate these UDPs but do not provide them.
primitive UDP_GF018hv5v_mcu_sc7_TT_1P8V_25C_verilog_nonpg_MGM_N_IQ_FF_UDP(Q, C, P, CK, D, N);
  output Q;
  reg Q;
  input C;
  input P;
  input CK;
  input D;
  input N;

  table
    1 1 ? ? 0 : ? : x;
    1 0 ? ? 0 : ? : 0;
    0 1 ? ? 0 : ? : 1;
    0 0 r 0 0 : ? : 0;
    0 0 r 1 0 : ? : 1;
    ? ? ? ? 1 : ? : x;
  endtable
endprimitive

primitive UDP_GF018hv5v_mcu_sc7_TT_1P8V_25C_verilog_nonpg_MGM_HN_IQ_FF_UDP(Q, C, P, CK, D, N);
  output Q;
  reg Q;
  input C;
  input P;
  input CK;
  input D;
  input N;

  table
    1 1 ? ? 0 : ? : x;
    1 0 ? ? 0 : ? : 0;
    0 1 ? ? 0 : ? : 1;
    0 0 r 0 0 : ? : 0;
    0 0 r 1 0 : ? : 1;
    ? ? ? ? 1 : ? : x;
  endtable
endprimitive

primitive UDP_GF018hv5v_mcu_sc7_TT_1P8V_25C_verilog_nonpg_MGM_N_IQ_LATCH_UDP(Q, C, P, E, D, N);
  output Q;
  reg Q;
  input C;
  input P;
  input E;
  input D;
  input N;

  table
    1 1 ? ? 0 : ? : x;
    1 0 ? ? 0 : ? : 0;
    0 1 ? ? 0 : ? : 1;
    0 0 1 0 0 : ? : 0;
    0 0 1 1 0 : ? : 1;
    ? ? ? ? 1 : ? : x;
  endtable
endprimitive

primitive UDP_GF018hv5v_mcu_sc7_TT_1P8V_25C_verilog_nonpg_MGM_HN_IQ_LATCH_UDP(Q, C, P, E, D, N);
  output Q;
  reg Q;
  input C;
  input P;
  input E;
  input D;
  input N;

  table
    1 1 ? ? 0 : ? : x;
    1 0 ? ? 0 : ? : 0;
    0 1 ? ? 0 : ? : 1;
    0 0 1 0 0 : ? : 0;
    0 0 1 1 0 : ? : 1;
    ? ? ? ? 1 : ? : x;
  endtable
endprimitive
