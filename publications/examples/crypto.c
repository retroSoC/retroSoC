#include <retrosoc/hal/crypto.h>

rs_status_t example_crypto(const uint8_t *key, size_t key_bytes, rs_timeout_t timeout)
{
    return rs_crypto_aes_set_key(key, key_bytes, timeout);
}
