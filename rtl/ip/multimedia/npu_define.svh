// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`ifndef RETROSOC_NPU_DEFINE_SVH
`define RETROSOC_NPU_DEFINE_SVH

// Handwritten NPU hardware/software ABI. Offsets, reset values, bit fields,
// result/fault enumerations, opcodes, and descriptor word positions follow
// docs/ip/npu.md "Register and Software ABI"; the C HAL header keeps parity.

// verilog_format: off -- keep the handwritten hardware/software ABI columns aligned
`define APB4_NPU__IP_ID                        12'h000
`define APB4_NPU__IP_VERSION                   12'h004
`define APB4_NPU__CAPABILITY                   12'h008
`define APB4_NPU__STATUS                       12'h00c
`define APB4_NPU__CONTROL                      12'h010
`define APB4_NPU__IRQ_STATE                    12'h014
`define APB4_NPU__IRQ_ENABLE                   12'h018
`define APB4_NPU__IRQ_TEST                     12'h01c
`define APB4_NPU__JOB_BASE                     12'h020
`define APB4_NPU__JOB_COUNT                    12'h024
`define APB4_NPU__JOB_ID                       12'h028
`define APB4_NPU__TIMEOUT_CYCLES               12'h02c
`define APB4_NPU__RESULT_JOB_ID                12'h030
`define APB4_NPU__RESULT_CODE                  12'h034
`define APB4_NPU__COMPLETED_DESCRIPTORS        12'h038
`define APB4_NPU__FAULT_DESCRIPTOR             12'h03c
`define APB4_NPU__FAULT_CODE                   12'h040
`define APB4_NPU__FAULT_ADDRESS                12'h044
`define APB4_NPU__FAULT_INFO                   12'h048
`define APB4_NPU__NUMERIC_PROFILE              12'h04c
`define APB4_NPU__LOCAL_BYTES                  12'h050
`define APB4_NPU__MAC_CONFIG                   12'h054
`define APB4_NPU__MAX_K_SLICE                  12'h058
`define APB4_NPU__MAX_DIMENSION                12'h05c
`define APB4_NPU__OP_CAPABILITY                12'h060
`define APB4_NPU__OWNER_STATUS                 12'h064
`define APB4_NPU__RECOVERY_GENERATION          12'h068
`define APB4_NPU__PERF_CONTROL                 12'h06c
`define APB4_NPU__PERF_STATUS                  12'h070
`define APB4_NPU__PERF_JOB_ID                  12'h074
`define APB4_NPU__PERF_GENERATION              12'h078
`define APB4_NPU__DESCRIPTOR_BYTES             12'h07c
`define APB4_NPU__PERF_ACTIVE_CYCLES_LO        12'h080
`define APB4_NPU__PERF_ACTIVE_CYCLES_HI        12'h084
`define APB4_NPU__PERF_CLOCK_PAUSE_CYCLES_LO   12'h088
`define APB4_NPU__PERF_CLOCK_PAUSE_CYCLES_HI   12'h08c
`define APB4_NPU__PERF_USEFUL_MACS_LO          12'h090
`define APB4_NPU__PERF_USEFUL_MACS_HI          12'h094
`define APB4_NPU__PERF_PACK_CYCLES_LO          12'h098
`define APB4_NPU__PERF_PACK_CYCLES_HI          12'h09c
`define APB4_NPU__PERF_LOCAL_BANK_STALL_LO     12'h0a0
`define APB4_NPU__PERF_LOCAL_BANK_STALL_HI     12'h0a4
`define APB4_NPU__PERF_DMA_READ_BYTES_LO       12'h0a8
`define APB4_NPU__PERF_DMA_READ_BYTES_HI       12'h0ac
`define APB4_NPU__PERF_DMA_WRITE_BYTES_LO      12'h0b0
`define APB4_NPU__PERF_DMA_WRITE_BYTES_HI      12'h0b4
`define APB4_NPU__PERF_DMA_STALL_CYCLES_LO     12'h0b8
`define APB4_NPU__PERF_DMA_STALL_CYCLES_HI     12'h0bc
`define APB4_NPU__PERF_REQUANT_STALL_LO        12'h0c0
`define APB4_NPU__PERF_REQUANT_STALL_HI        12'h0c4
`define APB4_NPU__PERF_RETIRED_DESCRIPTORS_LO  12'h0c8
`define APB4_NPU__PERF_RETIRED_DESCRIPTORS_HI  12'h0cc

`define APB4_NPU__IP_ID_VALUE                  32'h4e50_5531
`define APB4_NPU__IP_VERSION_VALUE             32'h0001_0000
`define APB4_NPU__CAPABILITY_P4                32'h0000_007f
`define APB4_NPU__NUMERIC_PROFILE_VALUE        32'h0000_0001
`define APB4_NPU__DESCRIPTOR_BYTES_VALUE       32'h0000_0080
`define APB4_NPU__LOCAL_BYTES_VALUE            32'h0001_0000
`define APB4_NPU__MAC_CONFIG_VALUE             32'h0008_0040
`define APB4_NPU__MAX_K_SLICE_VALUE            32'h0000_0400
`define APB4_NPU__MAX_DIMENSION_VALUE          32'h0000_1000
`define APB4_NPU__OP_CAPABILITY_VALUE          32'h0000_01fe
`define APB4_NPU__FAULT_DESCRIPTOR_RESET       32'hffff_ffff

`define APB4_NPU__CAPABILITY_PRESENT           0
`define APB4_NPU__CAPABILITY_EXECUTION_READY   1
`define APB4_NPU__CAPABILITY_PRIVATE_AXI64_DMA 2
`define APB4_NPU__CAPABILITY_INTERRUPTS        3
`define APB4_NPU__CAPABILITY_DOUBLE_ROUNDING   4
`define APB4_NPU__CAPABILITY_NATIVE_HP_CLOCK   5
`define APB4_NPU__CAPABILITY_SOFTWARE_ABORT    6

`define APB4_NPU__STATUS_READY                 0
`define APB4_NPU__STATUS_BUSY                  1
`define APB4_NPU__STATUS_DRAINING              2
`define APB4_NPU__STATUS_CLOCK_PAUSED          3
`define APB4_NPU__STATUS_RECOVERING            4
`define APB4_NPU__STATUS_RESULT_VALID          5

`define APB4_NPU__CONTROL_START                0
`define APB4_NPU__CONTROL_ABORT                1
`define APB4_NPU__CONTROL_SOFT_RESET           2

`define APB4_NPU__IRQ_DONE                     0
`define APB4_NPU__IRQ_ERROR                    1
`define APB4_NPU__IRQ_ABORTED                  2
`define APB4_NPU__IRQ_ALL                      3'h7

`define APB4_NPU__RESULT_CODE_NONE             0
`define APB4_NPU__RESULT_CODE_DONE             1
`define APB4_NPU__RESULT_CODE_ERROR            2
`define APB4_NPU__RESULT_CODE_ABORTED          3
`define APB4_NPU__RESULT_CODE_RESET_CANCELLED  4

`define APB4_NPU__FAULT_CODE_NONE              0
`define APB4_NPU__FAULT_CODE_DESCRIPTOR        1
`define APB4_NPU__FAULT_CODE_UNSUPPORTED       2
`define APB4_NPU__FAULT_CODE_RANGE             3
`define APB4_NPU__FAULT_CODE_AXI_READ          4
`define APB4_NPU__FAULT_CODE_AXI_WRITE         5
`define APB4_NPU__FAULT_CODE_AXI_PROTOCOL      6
`define APB4_NPU__FAULT_CODE_ARITHMETIC        7
`define APB4_NPU__FAULT_CODE_NO_PROGRESS       8
`define APB4_NPU__FAULT_CODE_LOCAL_STATE       9
`define APB4_NPU__FAULT_CODE_RESET_CANCELLED   10

`define APB4_NPU__FAULT_INFO_AXI_RESPONSE      0
`define APB4_NPU__FAULT_INFO_DIRECTION         2
`define APB4_NPU__FAULT_INFO_LANE              8

`define APB4_NPU__OWNER_STATUS_OWNER           0
`define APB4_NPU__OWNER_STATUS_LOCK            8
`define APB4_NPU__OWNER_STATUS_QUIESCE         9
`define APB4_NPU__OWNER_STATUS_RESET_REQUEST   10

`define APB4_NPU__PERF_CONTROL_SNAPSHOT        0
`define APB4_NPU__PERF_STATUS_SNAP_BUSY        0
`define APB4_NPU__PERF_STATUS_SNAP_VALID       1
`define APB4_NPU__PERF_COUNTER_COUNT           10

`define APB4_NPU__OP_CONV2D                    1
`define APB4_NPU__OP_DEPTHWISE3X3              2
`define APB4_NPU__OP_FULLY_CONNECTED           3
`define APB4_NPU__OP_ADD                       4
`define APB4_NPU__OP_MAX_POOL                  5
`define APB4_NPU__OP_AVERAGE_POOL              6
`define APB4_NPU__OP_GLOBAL_AVERAGE_POOL       7
`define APB4_NPU__OP_CLAMP                     8

`define APB4_NPU__DESCRIPTOR_VERSION           16'h0100
`define APB4_NPU__DESCRIPTOR_WORD_VERSION_OPCODE       0
`define APB4_NPU__DESCRIPTOR_WORD_RESERVED             1
`define APB4_NPU__DESCRIPTOR_WORD_INPUT0_BASE          2
`define APB4_NPU__DESCRIPTOR_WORD_INPUT1_BASE          3
`define APB4_NPU__DESCRIPTOR_WORD_OUTPUT_BASE          4
`define APB4_NPU__DESCRIPTOR_WORD_PARAM_BASE           5
`define APB4_NPU__DESCRIPTOR_WORD_INPUT_HW             6
`define APB4_NPU__DESCRIPTOR_WORD_CHANNELS             7
`define APB4_NPU__DESCRIPTOR_WORD_OUTPUT_HW            8
`define APB4_NPU__DESCRIPTOR_WORD_INPUT0_ROW_BYTES     9
`define APB4_NPU__DESCRIPTOR_WORD_OUTPUT_ROW_BYTES     10
`define APB4_NPU__DESCRIPTOR_WORD_INPUT1_ROW_BYTES     11
`define APB4_NPU__DESCRIPTOR_WORD_KERNEL_STRIDE        12
`define APB4_NPU__DESCRIPTOR_WORD_PADDING              13
`define APB4_NPU__DESCRIPTOR_WORD_TILE_HW              14
`define APB4_NPU__DESCRIPTOR_WORD_K_SLICE              15
`define APB4_NPU__DESCRIPTOR_WORD_INPUT0_BYTES         16
`define APB4_NPU__DESCRIPTOR_WORD_INPUT1_BYTES         17
`define APB4_NPU__DESCRIPTOR_WORD_OUTPUT_BYTES         18
`define APB4_NPU__DESCRIPTOR_WORD_PARAM_BYTES          19
`define APB4_NPU__DESCRIPTOR_WORD_INPUT0_ZERO          20
`define APB4_NPU__DESCRIPTOR_WORD_INPUT1_ZERO          21
`define APB4_NPU__DESCRIPTOR_WORD_OUTPUT_ZERO          22
`define APB4_NPU__DESCRIPTOR_WORD_ACTIVATION_BOUNDS    23
`define APB4_NPU__DESCRIPTOR_WORD_WEIGHT_BASE          24
`define APB4_NPU__DESCRIPTOR_WORD_WEIGHT_BYTES         25

// Shell/HP mailbox payload layouts: the hardware-internal ABI between npu_reg
// (PCLK) and npu_core (HP) carried by npu_control_cdc async_reqack instances.
`define APB4_NPU__LAUNCH_PAYLOAD_WIDTH         128
`define APB4_NPU__LAUNCH_JOB_BASE              0
`define APB4_NPU__LAUNCH_JOB_ID                32
`define APB4_NPU__LAUNCH_TIMEOUT_CYCLES        64
`define APB4_NPU__LAUNCH_JOB_COUNT             96

`define APB4_NPU__RESULT_PAYLOAD_WIDTH         170
`define APB4_NPU__RESULT_PAYLOAD_JOB_ID        0
`define APB4_NPU__RESULT_PAYLOAD_COMPLETED     32
`define APB4_NPU__RESULT_PAYLOAD_FAULT_DESC    64
`define APB4_NPU__RESULT_PAYLOAD_FAULT_ADDR    96
`define APB4_NPU__RESULT_PAYLOAD_FAULT_INFO    128
`define APB4_NPU__RESULT_PAYLOAD_CODE          160
`define APB4_NPU__RESULT_PAYLOAD_FAULT_CODE    163
`define APB4_NPU__RESULT_PAYLOAD_IRQ_EVENTS    167

`define APB4_NPU__SNAPSHOT_PAYLOAD_WIDTH       672
`define APB4_NPU__SNAPSHOT_PAYLOAD_JOB_ID      0
`define APB4_NPU__SNAPSHOT_PAYLOAD_COUNTERS    32

`define APB4_NPU__EPOCH_WIDTH                  4
// verilog_format: on

`endif
