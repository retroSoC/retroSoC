// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`ifndef RETROSOC_CRYPTO_DEFINE_SVH
`define RETROSOC_CRYPTO_DEFINE_SVH

// verilog_format: off -- software-visible register columns are manually mirrored in crypto_regs.h.
`define APB4_CRYPTO__IP_ID                 12'h000
`define APB4_CRYPTO__IP_VERSION            12'h004
`define APB4_CRYPTO__CAPABILITY0           12'h008
`define APB4_CRYPTO__CAPABILITY1           12'h00C
`define APB4_CRYPTO__COMMAND               12'h010
`define APB4_CRYPTO__STATUS                12'h014
`define APB4_CRYPTO__IRQ_STATE             12'h018
`define APB4_CRYPTO__IRQ_ENABLE            12'h01C
`define APB4_CRYPTO__IRQ_TEST              12'h020
`define APB4_CRYPTO__ERROR_STATUS          12'h024

`define APB4_CRYPTO__AES_CTRL              12'h100
`define APB4_CRYPTO__AES_CFG               12'h104
`define APB4_CRYPTO__AES_STATUS            12'h108
`define APB4_CRYPTO__AES_LENGTH            12'h10C
`define APB4_CRYPTO__AES_DATA_IN           12'h110
`define APB4_CRYPTO__AES_DATA_OUT          12'h114
`define APB4_CRYPTO__AES_DATA_STATUS       12'h118
`define APB4_CRYPTO__AES_BYTES_IN          12'h11C
`define APB4_CRYPTO__AES_BYTES_OUT         12'h120
`define APB4_CRYPTO__AES_CYCLES            12'h124
`define APB4_CRYPTO__AES_KEY_CTRL          12'h128
`define APB4_CRYPTO__AES_KEY_STATUS        12'h12C
`define APB4_CRYPTO__AES_KEY_BASE          12'h140
`define APB4_CRYPTO__AES_IV_BASE           12'h160
`define APB4_CRYPTO__AES_CHAIN_BASE        12'h170

`define APB4_CRYPTO__SHA_CTRL              12'h200
`define APB4_CRYPTO__SHA_CFG               12'h204
`define APB4_CRYPTO__SHA_STATUS            12'h208
`define APB4_CRYPTO__SHA_LENGTH_LO         12'h20C
`define APB4_CRYPTO__SHA_LENGTH_HI         12'h210
`define APB4_CRYPTO__SHA_DATA_IN           12'h214
`define APB4_CRYPTO__SHA_DATA_STATUS       12'h218
`define APB4_CRYPTO__SHA_BYTES_IN_LO       12'h21C
`define APB4_CRYPTO__SHA_BYTES_IN_HI       12'h220
`define APB4_CRYPTO__SHA_CYCLES            12'h224
`define APB4_CRYPTO__SHA_DIGEST_BASE       12'h240

`define APB4_CRYPTO__RSA_CTRL              12'h300
`define APB4_CRYPTO__RSA_CFG               12'h304
`define APB4_CRYPTO__RSA_STATUS            12'h308
`define APB4_CRYPTO__RSA_CYCLES            12'h30C
`define APB4_CRYPTO__RSA_PROGRESS          12'h310
`define APB4_CRYPTO__RSA_MODULUS_BASE      12'h400
`define APB4_CRYPTO__RSA_EXPONENT_BASE     12'h600
`define APB4_CRYPTO__RSA_BASE_BASE         12'h800
`define APB4_CRYPTO__RSA_RESULT_BASE       12'hA00

`define APB4_CRYPTO__COMMAND_ZEROIZE             0
`define APB4_CRYPTO__COMMAND_ABORT_AES           1
`define APB4_CRYPTO__COMMAND_ABORT_SHA           2
`define APB4_CRYPTO__COMMAND_ABORT_RSA           3
`define APB4_CRYPTO__AES_CTRL_START              0
`define APB4_CRYPTO__AES_CFG_MODE                0
`define APB4_CRYPTO__AES_CFG_DECRYPT             2
`define APB4_CRYPTO__AES_CFG_KEY_SIZE            4
`define APB4_CRYPTO__AES_CFG_DMA                 8
`define APB4_CRYPTO__AES_KEY_CTRL_COMMIT         0
`define APB4_CRYPTO__SHA_CTRL_START              0
`define APB4_CRYPTO__SHA_CFG_SHA256              0
`define APB4_CRYPTO__SHA_CFG_DMA                 8
`define APB4_CRYPTO__RSA_CTRL_PREPARE            0
`define APB4_CRYPTO__RSA_CTRL_PUBLIC             1
`define APB4_CRYPTO__RSA_CTRL_PRIVATE            2
`define APB4_CRYPTO__RSA_CFG_EXPONENT_BITS       0

`define APB4_CRYPTO__IRQ_AES_DONE                0
`define APB4_CRYPTO__IRQ_SHA_DONE                1
`define APB4_CRYPTO__IRQ_RSA_DONE                2
`define APB4_CRYPTO__IRQ_ERROR                   3
`define APB4_CRYPTO__IRQ_ZEROIZED                4

`define APB4_CRYPTO__ERROR_AES                   0
`define APB4_CRYPTO__ERROR_SHA                   1
`define APB4_CRYPTO__ERROR_RSA                   2
`define APB4_CRYPTO__ERROR_ACCESS                3
// verilog_format: on

`endif
