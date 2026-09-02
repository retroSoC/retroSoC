// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`ifndef RETROSOC_APU_DEFINE_SVH
`define RETROSOC_APU_DEFINE_SVH

// verilog_format: off -- keep the handwritten hardware/software ABI column aligned
`define APB4_APU__IP_ID                       12'h000
`define APB4_APU__IP_VERSION                  12'h004
`define APB4_APU__CAPABILITY0                 12'h008
`define APB4_APU__CAPABILITY1                 12'h00c
`define APB4_APU__COMMAND                     12'h010
`define APB4_APU__STATUS                      12'h014
`define APB4_APU__IRQ_STATE                   12'h018
`define APB4_APU__IRQ_ENABLE                  12'h01c
`define APB4_APU__IRQ_TEST                    12'h020
`define APB4_APU__ERROR_STATUS                12'h024
`define APB4_APU__ERROR_ADDRESS               12'h028
`define APB4_APU__ERROR_DETAIL                12'h02c
`define APB4_APU__SEQUENCER_TIMEOUT           12'h030
`define APB4_APU__STREAM_ROUTE                12'h034
`define APB4_APU__STREAM_STATUS               12'h038
`define APB4_APU__OWNER_STATUS                12'h03c
`define APB4_APU__READ_BASE                   12'h040
`define APB4_APU__READ_LIMIT                  12'h044
`define APB4_APU__WRITE_BASE                  12'h048
`define APB4_APU__WRITE_LIMIT                 12'h04c
`define APB4_APU__DMA_TIMEOUT                 12'h050
`define APB4_APU__ABI_DIGEST                  12'h054
`define APB4_APU__SEQUENCER_STATUS            12'h058
`define APB4_APU__SEQUENCER_RETIRED           12'h05c

`define APB4_APU__MC_IMAGE_ADDRESS            12'h080
`define APB4_APU__MC_IMAGE_SIZE               12'h084
`define APB4_APU__MC_EXPECTED_CRC             12'h088
`define APB4_APU__MC_STATUS                   12'h08c
`define APB4_APU__MC_ABI                      12'h090
`define APB4_APU__MC_BUILD_ID_LO              12'h094
`define APB4_APU__MC_BUILD_ID_HI              12'h098
`define APB4_APU__MC_LOCK                     12'h09c
`define APB4_APU__MC_ACTUAL_CRC               12'h0a0
`define APB4_APU__MC_LOAD_COUNT               12'h0a4

`define APB4_APU__JOB_CONTROL                 12'h100
`define APB4_APU__JOB_INPUT_ADDRESS           12'h104
`define APB4_APU__JOB_INPUT_LENGTH            12'h108
`define APB4_APU__JOB_OUTPUT_ADDRESS          12'h10c
`define APB4_APU__JOB_OUTPUT_CAPACITY         12'h110
`define APB4_APU__JOB_INPUT_CONFIG            12'h114
`define APB4_APU__JOB_OUTPUT_CONFIG           12'h118
`define APB4_APU__JOB_FLAGS                   12'h11c
`define APB4_APU__JOB_STATUS                  12'h120
`define APB4_APU__JOB_INPUT_USED              12'h124
`define APB4_APU__JOB_OUTPUT_BYTES            12'h128
`define APB4_APU__JOB_FRAMES                  12'h12c
`define APB4_APU__JOB_SOURCE_INFO             12'h130
`define APB4_APU__JOB_CYCLES                  12'h134
`define APB4_APU__JOB_DETAIL                  12'h138

`define APB4_APU__RING_BASE                   12'h180
`define APB4_APU__RING_SIZE                   12'h184
`define APB4_APU__RING_HEAD                   12'h188
`define APB4_APU__RING_TAIL                   12'h18c
`define APB4_APU__RING_CONTROL                12'h190
`define APB4_APU__RING_STATUS                 12'h194
`define APB4_APU__RING_COMPLETED              12'h198
`define APB4_APU__RING_COALESCE               12'h19c
`define APB4_APU__RING_DOORBELL               12'h1a0

`define APB4_APU__KWS_MODEL_ADDRESS           12'h200
`define APB4_APU__KWS_MODEL_SIZE              12'h204
`define APB4_APU__KWS_MODEL_EXPECTED_CRC      12'h208
`define APB4_APU__KWS_CONTROL                 12'h20c
`define APB4_APU__KWS_CONFIG                  12'h210
`define APB4_APU__KWS_STATUS                  12'h214
`define APB4_APU__KWS_RESULT                  12'h218
`define APB4_APU__KWS_TIMESTAMP_LO            12'h21c
`define APB4_APU__KWS_TIMESTAMP_HI            12'h220
`define APB4_APU__KWS_FRAME_COUNT             12'h224
`define APB4_APU__KWS_INFERENCE_COUNT         12'h228
`define APB4_APU__KWS_HIT_COUNT               12'h22c
`define APB4_APU__KWS_OVERRUN_COUNT           12'h230
`define APB4_APU__KWS_MODEL_STATUS            12'h234
`define APB4_APU__KWS_MODEL_ACTUAL_CRC        12'h238

`define APB4_APU__PERF_CONTROL                12'h300
`define APB4_APU__PERF_STATUS                 12'h304
`define APB4_APU__PERF_ACTIVE_CYCLES_LO       12'h308
`define APB4_APU__PERF_ACTIVE_CYCLES_HI       12'h30c
`define APB4_APU__PERF_INPUT_BYTES_LO         12'h310
`define APB4_APU__PERF_INPUT_BYTES_HI         12'h314
`define APB4_APU__PERF_OUTPUT_BYTES_LO        12'h318
`define APB4_APU__PERF_OUTPUT_BYTES_HI        12'h31c
`define APB4_APU__PERF_DECODED_FRAMES_LO      12'h320
`define APB4_APU__PERF_DECODED_FRAMES_HI      12'h324
`define APB4_APU__PERF_DMA_READ_STALLS_LO     12'h328
`define APB4_APU__PERF_DMA_READ_STALLS_HI     12'h32c
`define APB4_APU__PERF_DMA_WRITE_STALLS_LO    12'h330
`define APB4_APU__PERF_DMA_WRITE_STALLS_HI    12'h334
`define APB4_APU__PERF_STREAM_STALLS_LO       12'h338
`define APB4_APU__PERF_STREAM_STALLS_HI       12'h33c
`define APB4_APU__PERF_SEQUENCER_INSTR_LO     12'h340
`define APB4_APU__PERF_SEQUENCER_INSTR_HI     12'h344
`define APB4_APU__PERF_KWS_CYCLES_LO          12'h348
`define APB4_APU__PERF_KWS_CYCLES_HI          12'h34c
`define APB4_APU__PERF_FAULTS_LO              12'h350
`define APB4_APU__PERF_FAULTS_HI              12'h354

`define APB4_APU__CAPABILITY0_WAV             0
`define APB4_APU__CAPABILITY0_MP3             1
`define APB4_APU__CAPABILITY0_FLAC            2
`define APB4_APU__CAPABILITY0_PRIVATE_DMA     3
`define APB4_APU__CAPABILITY0_RING            4
`define APB4_APU__CAPABILITY0_STREAMS         5
`define APB4_APU__CAPABILITY0_KWS             6
`define APB4_APU__CAPABILITY0_SEQUENCER       7
`define APB4_APU__CAPABILITY0_RESAMPLER       8
`define APB4_APU__CAPABILITY1_CONTROL_KIB     0
`define APB4_APU__CAPABILITY1_DATA_KIB        8
`define APB4_APU__CAPABILITY1_MAX_CHANNELS    16
`define APB4_APU__CAPABILITY1_MAX_RATE_KHZ    18

`define APB4_APU__COMMAND_START_DIRECT        0
`define APB4_APU__COMMAND_ABORT               1
`define APB4_APU__COMMAND_SOFT_RESET          2
`define APB4_APU__COMMAND_RING_KICK           3
`define APB4_APU__COMMAND_MICROCODE_LOAD      4
`define APB4_APU__COMMAND_MODEL_LOAD          5
`define APB4_APU__COMMAND_CLEAR_COUNTERS      6

`define APB4_APU__STATUS_MICROCODE_VALID      0
`define APB4_APU__STATUS_MODEL_VALID          1
`define APB4_APU__STATUS_BUSY                 2
`define APB4_APU__STATUS_RING                 3
`define APB4_APU__STATUS_DECODE               4
`define APB4_APU__STATUS_KWS_LISTENING        5
`define APB4_APU__STATUS_QUIESCED             6
`define APB4_APU__STATUS_ABORTING             7
`define APB4_APU__STATUS_IDLE                 8
`define APB4_APU__STATUS_SEQUENCER_TRAPPED    9

`define APB4_APU__IRQ_DIRECT_DONE             0
`define APB4_APU__IRQ_RING_EVENT              1
`define APB4_APU__IRQ_KWS_HIT                 2
`define APB4_APU__IRQ_MICROCODE_LOAD_DONE     3
`define APB4_APU__IRQ_MODEL_LOAD_DONE         4
`define APB4_APU__IRQ_ABORT_DONE              5
`define APB4_APU__IRQ_INPUT_WATERMARK         6
`define APB4_APU__IRQ_OUTPUT_WATERMARK        7
`define APB4_APU__IRQ_FIRST_ERROR             8
`define APB4_APU__IRQ_STREAM_XRUN             9
`define APB4_APU__IRQ_SEQUENCER_TRAP          10

`define APB4_APU__ERROR_VALID                 0
`define APB4_APU__ERROR_CODE                  1
`define APB4_APU__ERROR_STAGE                 7
`define APB4_APU__ERROR_AXI_RESPONSE          11
`define APB4_APU__ERROR_DESCRIPTOR_INDEX      13

`define APB4_APU__ERROR_CODE_NONE             0
`define APB4_APU__ERROR_CODE_INVALID_CONFIG   1
`define APB4_APU__ERROR_CODE_INVALID_RING     2
`define APB4_APU__ERROR_CODE_UNSUPPORTED      3
`define APB4_APU__ERROR_CODE_MALFORMED        4
`define APB4_APU__ERROR_CODE_TRUNCATED        5
`define APB4_APU__ERROR_CODE_CODEC_CRC        6
`define APB4_APU__ERROR_CODE_DECODE           7
`define APB4_APU__ERROR_CODE_RECONSTRUCTION   8
`define APB4_APU__ERROR_CODE_MICROCODE        9
`define APB4_APU__ERROR_CODE_MICROCODE_CRC    10
`define APB4_APU__ERROR_CODE_SEQUENCER        11
`define APB4_APU__ERROR_CODE_KWS_MODEL        12
`define APB4_APU__ERROR_CODE_KWS_CRC          13
`define APB4_APU__ERROR_CODE_KWS_ARITHMETIC   14
`define APB4_APU__ERROR_CODE_AXI_READ         15
`define APB4_APU__ERROR_CODE_AXI_WRITE        16
`define APB4_APU__ERROR_CODE_DMA_TIMEOUT      17
`define APB4_APU__ERROR_CODE_STREAM_UNDERRUN  18
`define APB4_APU__ERROR_CODE_STREAM_OVERRUN   19
`define APB4_APU__ERROR_CODE_ABORT            20
`define APB4_APU__ERROR_CODE_RESOURCE_RESET   21
`define APB4_APU__ERROR_CODE_OVERFLOW         22

`define APB4_APU__ERROR_STAGE_APB             0
`define APB4_APU__ERROR_STAGE_LOADER          1
`define APB4_APU__ERROR_STAGE_RING            2
`define APB4_APU__ERROR_STAGE_DMA_READ        3
`define APB4_APU__ERROR_STAGE_BITSTREAM       4
`define APB4_APU__ERROR_STAGE_ENTROPY         5
`define APB4_APU__ERROR_STAGE_RECONSTRUCTION  6
`define APB4_APU__ERROR_STAGE_RESAMPLER       7
`define APB4_APU__ERROR_STAGE_DMA_WRITE       8
`define APB4_APU__ERROR_STAGE_KWS_FRONTEND    9
`define APB4_APU__ERROR_STAGE_KWS_INFERENCE   10
`define APB4_APU__ERROR_STAGE_LIFECYCLE       11

`define APB4_APU__OWNER_STATUS_OWNER          0
`define APB4_APU__OWNER_STATUS_LOCK           8
`define APB4_APU__OWNER_STATUS_QUIESCE        9
`define APB4_APU__OWNER_STATUS_RESET          10
`define APB4_APU__PERF_CONTROL_ENABLE         0
`define APB4_APU__PERF_CONTROL_CLEAR          1
`define APB4_APU__PERF_CONTROL_SNAPSHOT       2
`define APB4_APU__PERF_STATUS_SNAPSHOT_VALID  0
// verilog_format: on

`endif
