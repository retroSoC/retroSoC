#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/wait.h>
#include <retrosoc/hal/crypto.h>
#include <retrosoc/hal/dma.h>

#define RS_CRYPTO_AES_BLOCK_BYTES   16U
#define RS_CRYPTO_STREAM_WORD_BYTES 4U

static uint32_t rs_crypto_pack_word(const uint8_t *bytes, size_t byte_count) {
    uint32_t value = 0U;
    size_t index;

    for (index = 0U; index < byte_count; ++index) {
        value |= (uint32_t)bytes[index] << (index * 8U);
    }
    return value;
}

static rs_status_t rs_crypto_pio_store(uint32_t offset, const uint8_t *bytes, size_t byte_count) {
    const uintptr_t address = (uintptr_t)RS_SOC_APB4_CRYPTO_BASE + (uintptr_t)offset;

    if ((bytes == NULL) || (byte_count == 0U) || (byte_count > RS_CRYPTO_STREAM_WORD_BYTES)) {
        return RS_EINVAL;
    }
    if (byte_count == 1U) {
        *(volatile uint8_t *)address = bytes[0];
    } else if (byte_count == 2U) {
        *(volatile uint16_t *)address = (uint16_t)rs_crypto_pack_word(bytes, byte_count);
    } else if (byte_count == RS_CRYPTO_STREAM_WORD_BYTES) {
        *(volatile uint32_t *)address = rs_crypto_pack_word(bytes, byte_count);
    } else {
        return RS_EINVAL;
    }
    return RS_OK;
}

static void rs_crypto_unpack_word(uint32_t value, uint8_t *bytes, size_t byte_count) {
    size_t index;

    for (index = 0U; index < byte_count; ++index) {
        bytes[index] = (uint8_t)(value >> (index * 8U));
    }
}

static bool rs_crypto_bytes_equal(const uint8_t *left, const uint8_t *right, size_t byte_count) {
    size_t index;
    uint8_t difference = 0U;

    for (index = 0U; index < byte_count; ++index) {
        difference |= left[index] ^ right[index];
    }
    return difference == 0U;
}

static rs_status_t rs_crypto_aes_configure(rs_crypto_aes_mode_t mode, bool decrypt,
                                           const uint8_t iv[RS_CRYPTO_AES_BLOCK_BYTES],
                                           size_t byte_count, bool dma) {
    uint32_t config;
    size_t word_index;

    if ((mode > RS_CRYPTO_AES_CTR) || (byte_count == 0U) || (byte_count > UINT32_MAX) ||
        ((mode != RS_CRYPTO_AES_CTR) && ((byte_count % (size_t)RS_CRYPTO_AES_BLOCK_BYTES) != 0U)) ||
        ((mode != RS_CRYPTO_AES_ECB) && (iv == NULL))) {
        return RS_EINVAL;
    }
    if ((RS_CRYPTO_REG(RS_CRYPTO_REG_AES_STATUS) & RS_CRYPTO_AES_STATUS_BUSY) != 0U) {
        return RS_EIO;
    }

    config = RS_CRYPTO_REG(RS_CRYPTO_REG_AES_CFG) & RS_CRYPTO_AES_CFG_KEY_SIZE_MASK;
    config |= (uint32_t)mode << RS_CRYPTO_AES_CFG_MODE_SHIFT;
    if (decrypt) {
        config |= RS_CRYPTO_AES_CFG_DECRYPT;
    }
    if (dma) {
        config |= RS_CRYPTO_AES_CFG_DMA;
    }
    RS_CRYPTO_REG(RS_CRYPTO_REG_AES_CFG) = config;
    RS_CRYPTO_REG(RS_CRYPTO_REG_AES_LENGTH) = (uint32_t)byte_count;
    for (word_index = 0U; word_index < 4U; ++word_index) {
        RS_CRYPTO_ARRAY_REG(RS_CRYPTO_REG_AES_IV_BASE, word_index) =
            (iv == NULL) ? 0U : rs_crypto_pack_word(&iv[word_index * 4U], 4U);
    }
    RS_CRYPTO_REG(RS_CRYPTO_REG_IRQ_STATE) = RS_CRYPTO_IRQ_AES_DONE | RS_CRYPTO_IRQ_ERROR;
    RS_CRYPTO_REG(RS_CRYPTO_REG_ERROR_STATUS) = RS_CRYPTO_ERROR_ALL;
    return RS_OK;
}

rs_status_t rs_crypto_aes_set_key(const uint8_t *key, size_t key_bytes, rs_timeout_t timeout) {
    uint32_t key_size;
    uint32_t config;
    size_t word_index;

    if (key == NULL) {
        return RS_EINVAL;
    }
    if (key_bytes == 16U) {
        key_size = 0U;
    } else if (key_bytes == 24U) {
        key_size = 1U;
    } else if (key_bytes == 32U) {
        key_size = 2U;
    } else {
        return RS_EINVAL;
    }
    if ((RS_CRYPTO_REG(RS_CRYPTO_REG_STATUS) &
         (RS_CRYPTO_STATUS_AES_BUSY | RS_CRYPTO_STATUS_SHA_BUSY | RS_CRYPTO_STATUS_RSA_BUSY)) !=
        0U) {
        return RS_EIO;
    }

    config = RS_CRYPTO_REG(RS_CRYPTO_REG_AES_CFG) & ~RS_CRYPTO_AES_CFG_KEY_SIZE_MASK;
    config |= key_size << RS_CRYPTO_AES_CFG_KEY_SIZE_SHIFT;
    RS_CRYPTO_REG(RS_CRYPTO_REG_AES_CFG) = config;
    for (word_index = 0U; word_index < 8U; ++word_index) {
        RS_CRYPTO_ARRAY_REG(RS_CRYPTO_REG_AES_KEY_BASE, word_index) =
            ((word_index * 4U) < key_bytes)
                ? rs_crypto_pack_word(&key[word_index * 4U], RS_CRYPTO_STREAM_WORD_BYTES)
                : 0U;
    }
    RS_CRYPTO_REG(RS_CRYPTO_REG_AES_KEY_CTRL) = RS_CRYPTO_AES_KEY_CTRL_COMMIT;
    return rs_wait_mask(&RS_CRYPTO_REG(RS_CRYPTO_REG_AES_KEY_STATUS),
                        RS_CRYPTO_AES_KEY_STATUS_VALID, RS_CRYPTO_AES_KEY_STATUS_VALID, timeout);
}

rs_status_t rs_crypto_aes_crypt(rs_crypto_aes_mode_t mode, bool decrypt, const uint8_t iv[16],
                                const void *input, void *output, size_t byte_count,
                                rs_timeout_t timeout) {
    const uint8_t *input_bytes = (const uint8_t *)input;
    uint8_t *output_bytes = (uint8_t *)output;
    size_t input_offset = 0U;
    size_t output_offset = 0U;
    rs_status_t result;

    if ((input == NULL) || (output == NULL)) {
        return RS_EINVAL;
    }
    result = rs_crypto_aes_configure(mode, decrypt, iv, byte_count, false);
    if (result != RS_OK) {
        return result;
    }
    RS_CRYPTO_REG(RS_CRYPTO_REG_AES_CTRL) = RS_CRYPTO_AES_CTRL_START;

    while ((output_offset < byte_count) && (timeout != 0U)) {
        const uint32_t status = RS_CRYPTO_REG(RS_CRYPTO_REG_AES_DATA_STATUS);

        --timeout;
        if ((RS_CRYPTO_REG(RS_CRYPTO_REG_AES_STATUS) & RS_CRYPTO_AES_STATUS_ERROR) != 0U) {
            return RS_EIO;
        }
        if ((input_offset < byte_count) && ((status & RS_CRYPTO_AES_DATA_INPUT_READY) != 0U)) {
            size_t chunk = byte_count - input_offset;

            if (chunk > RS_CRYPTO_STREAM_WORD_BYTES) {
                chunk = RS_CRYPTO_STREAM_WORD_BYTES;
            } else if (chunk == 3U) {
                chunk = 2U;
            }
            result =
                rs_crypto_pio_store(RS_CRYPTO_REG_AES_DATA_IN, &input_bytes[input_offset], chunk);
            if (result != RS_OK) {
                return result;
            }
            input_offset += chunk;
        }
        if ((status & RS_CRYPTO_AES_DATA_OUTPUT_VALID) != 0U) {
            size_t chunk = byte_count - output_offset;
            uint32_t word;

            if (chunk > RS_CRYPTO_STREAM_WORD_BYTES) {
                chunk = RS_CRYPTO_STREAM_WORD_BYTES;
            }
            word = RS_CRYPTO_REG(RS_CRYPTO_REG_AES_DATA_OUT);
            rs_crypto_unpack_word(word, &output_bytes[output_offset], chunk);
            output_offset += chunk;
        }
    }
    if (output_offset != byte_count) {
        return RS_ETIMEOUT;
    }
    return ((RS_CRYPTO_REG(RS_CRYPTO_REG_AES_STATUS) & RS_CRYPTO_AES_STATUS_ERROR) == 0U) ? RS_OK
                                                                                          : RS_EIO;
}

static bool rs_crypto_ranges_overlap(uintptr_t left, uintptr_t right, size_t byte_count) {
    return (left <= right) ? ((right - left) < byte_count) : ((left - right) < byte_count);
}

rs_status_t rs_crypto_aes_crypt_dma(rs_crypto_aes_mode_t mode, bool decrypt, const uint8_t iv[16],
                                    const void *input, void *output, size_t byte_count,
                                    rs_timeout_t timeout) {
    const uintptr_t source = (uintptr_t)input;
    const uintptr_t destination = (uintptr_t)output;
    const rs_dma_config_t input_config = {
        .kind = RS_DMA_KIND_MM_TO_STREAM,
        .request = RS_DMA_REQUEST_CRYPTO_IN,
        .source = source,
        .destination = (uintptr_t)0U,
        .byte_count = (uint32_t)byte_count,
        .width = RS_DMA_WIDTH_32,
        .source_increment = true,
        .destination_increment = false,
        .priority = 3U,
        .burst_beats = RS_DMA_MAX_BURST_BEATS,
    };
    const rs_dma_config_t output_config = {
        .kind = RS_DMA_KIND_STREAM_TO_MM,
        .request = RS_DMA_REQUEST_CRYPTO_OUT,
        .source = (uintptr_t)0U,
        .destination = destination,
        .byte_count = (uint32_t)byte_count,
        .width = RS_DMA_WIDTH_32,
        .source_increment = false,
        .destination_increment = true,
        .priority = 3U,
        .burst_beats = RS_DMA_MAX_BURST_BEATS,
    };
    rs_status_t result;

    if ((input == NULL) || (output == NULL) || (byte_count > UINT32_MAX) ||
        ((source % RS_CRYPTO_DMA_ALIGNMENT) != 0U) ||
        ((destination % RS_CRYPTO_DMA_ALIGNMENT) != 0U) ||
        ((byte_count % RS_CRYPTO_DMA_ALIGNMENT) != 0U) ||
        rs_crypto_ranges_overlap(source, destination, byte_count)) {
        return RS_EINVAL;
    }
    result = rs_crypto_aes_configure(mode, decrypt, iv, byte_count, true);
    if (result == RS_OK) {
        result = rs_dma_configure(RS_DMA_CHANNEL_CRYPTO_IN, &input_config);
    }
    if (result == RS_OK) {
        result = rs_dma_configure(RS_DMA_CHANNEL_CRYPTO_OUT, &output_config);
    }
    if (result == RS_OK) {
        result = rs_dma_start(RS_DMA_CHANNEL_CRYPTO_OUT);
    }
    if (result == RS_OK) {
        RS_CRYPTO_REG(RS_CRYPTO_REG_AES_CTRL) = RS_CRYPTO_AES_CTRL_START;
        result = rs_dma_start(RS_DMA_CHANNEL_CRYPTO_IN);
    }
    if (result == RS_OK) {
        result = rs_dma_wait(RS_DMA_CHANNEL_CRYPTO_IN, timeout);
    }
    if (result == RS_OK) {
        result = rs_dma_wait(RS_DMA_CHANNEL_CRYPTO_OUT, timeout);
    }
    if ((result == RS_OK) &&
        ((RS_CRYPTO_REG(RS_CRYPTO_REG_AES_STATUS) & RS_CRYPTO_AES_STATUS_ERROR) != 0U)) {
        result = RS_EIO;
    }
    if (result != RS_OK) {
        RS_CRYPTO_REG(RS_CRYPTO_REG_COMMAND) = RS_CRYPTO_COMMAND_ABORT_AES;
        (void)rs_dma_abort_wait(RS_DMA_CHANNEL_CRYPTO_IN, timeout);
        (void)rs_dma_abort_wait(RS_DMA_CHANNEL_CRYPTO_OUT, timeout);
    }
    return result;
}

rs_status_t rs_crypto_sha2(bool sha256, const void *input, size_t byte_count, uint8_t digest[32],
                           rs_timeout_t timeout) {
    const uint8_t *input_bytes = (const uint8_t *)input;
    size_t input_offset = 0U;
    size_t word_index;

    if ((digest == NULL) || ((byte_count != 0U) && (input == NULL))) {
        return RS_EINVAL;
    }
    if ((RS_CRYPTO_REG(RS_CRYPTO_REG_SHA_STATUS) & RS_CRYPTO_SHA_STATUS_BUSY) != 0U) {
        return RS_EIO;
    }
    RS_CRYPTO_REG(RS_CRYPTO_REG_SHA_CFG) = sha256 ? RS_CRYPTO_SHA_CFG_SHA256 : 0U;
    RS_CRYPTO_REG(RS_CRYPTO_REG_SHA_LENGTH_LO) = (uint32_t)byte_count;
#if SIZE_MAX > UINT32_MAX
    RS_CRYPTO_REG(RS_CRYPTO_REG_SHA_LENGTH_HI) = (uint32_t)(byte_count >> 32U);
#else
    RS_CRYPTO_REG(RS_CRYPTO_REG_SHA_LENGTH_HI) = 0U;
#endif
    RS_CRYPTO_REG(RS_CRYPTO_REG_IRQ_STATE) = RS_CRYPTO_IRQ_SHA_DONE | RS_CRYPTO_IRQ_ERROR;
    RS_CRYPTO_REG(RS_CRYPTO_REG_ERROR_STATUS) = RS_CRYPTO_ERROR_ALL;
    RS_CRYPTO_REG(RS_CRYPTO_REG_SHA_CTRL) = RS_CRYPTO_SHA_CTRL_START;

    while ((input_offset < byte_count) && (timeout != 0U)) {
        const uint32_t status = RS_CRYPTO_REG(RS_CRYPTO_REG_SHA_DATA_STATUS);

        --timeout;
        if ((RS_CRYPTO_REG(RS_CRYPTO_REG_SHA_STATUS) & RS_CRYPTO_SHA_STATUS_ERROR) != 0U) {
            return RS_EIO;
        }
        if ((status & RS_CRYPTO_SHA_DATA_INPUT_READY) != 0U) {
            size_t chunk = byte_count - input_offset;
            rs_status_t result;

            if (chunk > RS_CRYPTO_STREAM_WORD_BYTES) {
                chunk = RS_CRYPTO_STREAM_WORD_BYTES;
            } else if (chunk == 3U) {
                chunk = 2U;
            }
            result =
                rs_crypto_pio_store(RS_CRYPTO_REG_SHA_DATA_IN, &input_bytes[input_offset], chunk);
            if (result != RS_OK) {
                return result;
            }
            input_offset += chunk;
        }
    }
    if (input_offset != byte_count) {
        return RS_ETIMEOUT;
    }
    if (rs_wait_mask(&RS_CRYPTO_REG(RS_CRYPTO_REG_SHA_STATUS), RS_CRYPTO_SHA_STATUS_DIGEST_VALID,
                     RS_CRYPTO_SHA_STATUS_DIGEST_VALID, timeout) != RS_OK) {
        return RS_ETIMEOUT;
    }
    if ((RS_CRYPTO_REG(RS_CRYPTO_REG_SHA_STATUS) & RS_CRYPTO_SHA_STATUS_ERROR) != 0U) {
        return RS_EIO;
    }
    for (word_index = 0U; word_index < 8U; ++word_index) {
        const uint32_t word = RS_CRYPTO_ARRAY_REG(RS_CRYPTO_REG_SHA_DIGEST_BASE, word_index);

        digest[(word_index * 4U)] = (uint8_t)(word >> 24U);
        digest[(word_index * 4U) + 1U] = (uint8_t)(word >> 16U);
        digest[(word_index * 4U) + 2U] = (uint8_t)(word >> 8U);
        digest[(word_index * 4U) + 3U] = (uint8_t)word;
    }
    return RS_OK;
}

rs_status_t rs_crypto_rsa_prepare(const uint32_t modulus[RS_CRYPTO_RSA_WORDS],
                                  rs_timeout_t timeout) {
    size_t word_index;

    if ((modulus == NULL) || ((modulus[0] & 1U) == 0U) ||
        ((modulus[RS_CRYPTO_RSA_WORDS - 1U] & UINT32_C(0x80000000)) == 0U)) {
        return RS_EINVAL;
    }
    if ((RS_CRYPTO_REG(RS_CRYPTO_REG_RSA_STATUS) & RS_CRYPTO_RSA_STATUS_BUSY) != 0U) {
        return RS_EIO;
    }
    for (word_index = 0U; word_index < RS_CRYPTO_RSA_WORDS; ++word_index) {
        RS_CRYPTO_ARRAY_REG(RS_CRYPTO_REG_RSA_MODULUS_BASE, word_index) = modulus[word_index];
    }
    RS_CRYPTO_REG(RS_CRYPTO_REG_RSA_CTRL) = RS_CRYPTO_RSA_CTRL_PREPARE;
    if (rs_wait_mask(&RS_CRYPTO_REG(RS_CRYPTO_REG_RSA_STATUS), RS_CRYPTO_RSA_STATUS_BUSY, 0U,
                     timeout) != RS_OK) {
        return RS_ETIMEOUT;
    }
    return ((RS_CRYPTO_REG(RS_CRYPTO_REG_RSA_STATUS) &
             (RS_CRYPTO_RSA_STATUS_ERROR | RS_CRYPTO_RSA_STATUS_PREPARED)) ==
            RS_CRYPTO_RSA_STATUS_PREPARED)
               ? RS_OK
               : RS_EIO;
}

rs_status_t rs_crypto_rsa_modexp(const uint32_t base[RS_CRYPTO_RSA_WORDS],
                                 const uint32_t exponent[RS_CRYPTO_RSA_WORDS],
                                 uint16_t exponent_bits, bool private_operation,
                                 uint32_t result[RS_CRYPTO_RSA_WORDS], rs_timeout_t timeout) {
    size_t word_index;
    uint32_t command;

    if ((base == NULL) || (exponent == NULL) || (result == NULL) ||
        (!private_operation && ((exponent_bits == 0U) || (exponent_bits > 2048U)))) {
        return RS_EINVAL;
    }
    if ((RS_CRYPTO_REG(RS_CRYPTO_REG_RSA_STATUS) &
         (RS_CRYPTO_RSA_STATUS_BUSY | RS_CRYPTO_RSA_STATUS_PREPARED)) !=
        RS_CRYPTO_RSA_STATUS_PREPARED) {
        return RS_EIO;
    }
    for (word_index = 0U; word_index < RS_CRYPTO_RSA_WORDS; ++word_index) {
        RS_CRYPTO_ARRAY_REG(RS_CRYPTO_REG_RSA_EXPONENT_BASE, word_index) = exponent[word_index];
        RS_CRYPTO_ARRAY_REG(RS_CRYPTO_REG_RSA_BASE_BASE, word_index) = base[word_index];
    }
    RS_CRYPTO_REG(RS_CRYPTO_REG_RSA_CFG) = private_operation ? 2048U : exponent_bits;
    command = private_operation ? RS_CRYPTO_RSA_CTRL_PRIVATE : RS_CRYPTO_RSA_CTRL_PUBLIC;
    RS_CRYPTO_REG(RS_CRYPTO_REG_RSA_CTRL) = command;
    if (rs_wait_mask(&RS_CRYPTO_REG(RS_CRYPTO_REG_RSA_STATUS), RS_CRYPTO_RSA_STATUS_BUSY, 0U,
                     timeout) != RS_OK) {
        return RS_ETIMEOUT;
    }
    if ((RS_CRYPTO_REG(RS_CRYPTO_REG_RSA_STATUS) &
         (RS_CRYPTO_RSA_STATUS_ERROR | RS_CRYPTO_RSA_STATUS_RESULT_VALID)) !=
        RS_CRYPTO_RSA_STATUS_RESULT_VALID) {
        return RS_EIO;
    }
    for (word_index = 0U; word_index < RS_CRYPTO_RSA_WORDS; ++word_index) {
        result[word_index] = RS_CRYPTO_ARRAY_REG(RS_CRYPTO_REG_RSA_RESULT_BASE, word_index);
    }
    return RS_OK;
}

rs_status_t rs_crypto_zeroize(void) {
    RS_CRYPTO_REG(RS_CRYPTO_REG_COMMAND) = RS_CRYPTO_COMMAND_ZEROIZE;
    return ((RS_CRYPTO_REG(RS_CRYPTO_REG_AES_KEY_STATUS) & RS_CRYPTO_AES_STATUS_KEY_VALID) == 0U)
               ? RS_OK
               : RS_EIO;
}

rs_status_t rs_crypto_selftest(rs_timeout_t timeout) {
    static const uint8_t Key[16] = {
        0x00U, 0x01U, 0x02U, 0x03U, 0x04U, 0x05U, 0x06U, 0x07U,
        0x08U, 0x09U, 0x0aU, 0x0bU, 0x0cU, 0x0dU, 0x0eU, 0x0fU,
    };
    static const uint8_t Plaintext[16] = {
        0x00U, 0x11U, 0x22U, 0x33U, 0x44U, 0x55U, 0x66U, 0x77U,
        0x88U, 0x99U, 0xaaU, 0xbbU, 0xccU, 0xddU, 0xeeU, 0xffU,
    };
    static const uint8_t Ciphertext[16] = {
        0x69U, 0xc4U, 0xe0U, 0xd8U, 0x6aU, 0x7bU, 0x04U, 0x30U,
        0xd8U, 0xcdU, 0xb7U, 0x80U, 0x70U, 0xb4U, 0xc5U, 0x5aU,
    };
    static const uint8_t Message[3] = {0x61U, 0x62U, 0x63U};
    static const uint8_t Digest[32] = {
        0xbaU, 0x78U, 0x16U, 0xbfU, 0x8fU, 0x01U, 0xcfU, 0xeaU, 0x41U, 0x41U, 0x40U,
        0xdeU, 0x5dU, 0xaeU, 0x22U, 0x23U, 0xb0U, 0x03U, 0x61U, 0xa3U, 0x96U, 0x17U,
        0x7aU, 0x9cU, 0xb4U, 0x10U, 0xffU, 0x61U, 0xf2U, 0x00U, 0x15U, 0xadU,
    };
    uint8_t output[32];
    rs_status_t result;

    result = rs_crypto_aes_set_key(Key, sizeof(Key), timeout);
    if (result == RS_OK) {
        result = rs_crypto_aes_crypt(RS_CRYPTO_AES_ECB, false, NULL, Plaintext, output,
                                     sizeof(Plaintext), timeout);
    }
    if ((result == RS_OK) && !rs_crypto_bytes_equal(output, Ciphertext, sizeof(Ciphertext))) {
        result = RS_EIO;
    }
    if (result == RS_OK) {
        result = rs_crypto_sha2(true, Message, sizeof(Message), output, timeout);
    }
    if ((result == RS_OK) && !rs_crypto_bytes_equal(output, Digest, sizeof(Digest))) {
        result = RS_EIO;
    }
    if (rs_crypto_zeroize() != RS_OK) {
        result = RS_EIO;
    }
    return result;
}
