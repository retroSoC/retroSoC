#include <stddef.h>
#include <stdint.h>

#include <retrosoc/hal/crypto.h>
#include <retrosoc/service/test.h>

/* Focused LP acceptance image. It uses only public HAL calls and the real
 * DMA channels, SRAM, APB bridge and Crypto endpoint in the full SoC. */
int main(void) {
    static const uint8_t key[16] = {
        0x00U, 0x01U, 0x02U, 0x03U, 0x04U, 0x05U, 0x06U, 0x07U,
        0x08U, 0x09U, 0x0AU, 0x0BU, 0x0CU, 0x0DU, 0x0EU, 0x0FU,
    };
    static const uint32_t input[16] = {
        UINT32_C(0x33221100), UINT32_C(0x77665544), UINT32_C(0xBBAA9988), UINT32_C(0xFFEEDDCC),
        UINT32_C(0x33221100), UINT32_C(0x77665544), UINT32_C(0xBBAA9988), UINT32_C(0xFFEEDDCC),
        UINT32_C(0x33221100), UINT32_C(0x77665544), UINT32_C(0xBBAA9988), UINT32_C(0xFFEEDDCC),
        UINT32_C(0x33221100), UINT32_C(0x77665544), UINT32_C(0xBBAA9988), UINT32_C(0xFFEEDDCC),
    };
    static const uint32_t expected[4] = {
        UINT32_C(0xD8E0C469),
        UINT32_C(0x30047B6A),
        UINT32_C(0x80B7CDD8),
        UINT32_C(0x5AC5B470),
    };
    static uint32_t output[16];

    /* Exercise the real APB guard before any constant image is initialized. */
    if (rs_crypto_zeroize_wait(1U) != RS_ETIMEOUT) {
        rs_test_finish(RS_TEST_FAILED, 8U);
    }
    if (rs_crypto_zeroize_wait(RS_TIMEOUT_DEFAULT) != RS_OK) {
        rs_test_finish(RS_TEST_FAILED, 9U);
    }
    /* BEGIN + 2048 words + COMMIT exhaust this budget during verification.
     * Cancellation may leave scrub active, and the following init must wait. */
    if (rs_crypto_init(2050U) != RS_ETIMEOUT) {
        rs_test_finish(RS_TEST_FAILED, 10U);
    }
    if (rs_crypto_selftest(RS_TIMEOUT_DEFAULT) != RS_OK) {
        rs_test_finish(RS_TEST_FAILED, 1U);
    }
    if (rs_crypto_init(0U) != RS_OK) {
        rs_test_finish(RS_TEST_FAILED, 2U);
    }
    if (rs_crypto_aes_set_key(key, sizeof(key), RS_TIMEOUT_DEFAULT) != RS_OK) {
        rs_test_finish(RS_TEST_FAILED, 3U);
    }
    if (rs_crypto_aes_crypt_dma(RS_CRYPTO_AES_ECB, false, NULL, input, output, sizeof(input),
                                RS_TIMEOUT_DEFAULT) != RS_OK) {
        rs_test_finish(RS_TEST_FAILED, 4U);
    }
    for (size_t index = 0U; index < 16U; ++index) {
        if (output[index] != expected[index % 4U]) {
            rs_test_finish(RS_TEST_FAILED, 5U);
        }
    }
    if (rs_crypto_zeroize_wait(0U) != RS_ETIMEOUT) {
        rs_test_finish(RS_TEST_FAILED, 6U);
    }
    if (rs_crypto_zeroize_wait(RS_TIMEOUT_DEFAULT) != RS_OK) {
        rs_test_finish(RS_TEST_FAILED, 7U);
    }
    rs_test_finish(RS_TEST_PASSED, 0U);
    return 0;
}
