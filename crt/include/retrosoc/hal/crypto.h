#ifndef RETROSOC_HAL_CRYPTO_H
#define RETROSOC_HAL_CRYPTO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/hal/crypto_regs.h>

typedef enum {
    RS_CRYPTO_AES_ECB = 0,
    RS_CRYPTO_AES_CBC = 1,
    RS_CRYPTO_AES_CTR = 2,
} rs_crypto_aes_mode_t;

rs_status_t rs_crypto_aes_set_key(const uint8_t *key, size_t key_bytes, rs_timeout_t timeout);
rs_status_t rs_crypto_aes_crypt(rs_crypto_aes_mode_t mode, bool decrypt, const uint8_t iv[16],
                                const void *input, void *output, size_t byte_count,
                                rs_timeout_t timeout);
rs_status_t rs_crypto_aes_crypt_dma(rs_crypto_aes_mode_t mode, bool decrypt, const uint8_t iv[16],
                                    const void *input, void *output, size_t byte_count,
                                    rs_timeout_t timeout);
rs_status_t rs_crypto_sha2(bool sha256, const void *input, size_t byte_count, uint8_t digest[32],
                           rs_timeout_t timeout);
rs_status_t rs_crypto_rsa_prepare(const uint32_t modulus[RS_CRYPTO_RSA_WORDS],
                                  rs_timeout_t timeout);
rs_status_t rs_crypto_rsa_modexp(const uint32_t base[RS_CRYPTO_RSA_WORDS],
                                 const uint32_t exponent[RS_CRYPTO_RSA_WORDS],
                                 uint16_t exponent_bits, bool private_operation,
                                 uint32_t result[RS_CRYPTO_RSA_WORDS], rs_timeout_t timeout);
rs_status_t rs_crypto_zeroize(void);
rs_status_t rs_crypto_selftest(rs_timeout_t timeout);

#endif
