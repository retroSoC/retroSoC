#include <stdbool.h>
#include <stdint.h>

#include <retrosoc/hal/crypto.h>

#include "crypto_constants.h"

#define RS_CRYPTO_ENGINE_BUSY_MASK                                                                 \
    (RS_CRYPTO_STATUS_AES_BUSY | RS_CRYPTO_STATUS_SHA_BUSY | RS_CRYPTO_STATUS_RSA_BUSY)
#define RS_CRYPTO_IMAGE_READY_MASK                                                                 \
    (RS_CRYPTO_MEM_STATUS_READY | RS_CRYPTO_MEM_STATUS_TABLE_VALID |                               \
     RS_CRYPTO_MEM_STATUS_TABLE_LOCKED)

static rs_status_t rs_crypto_v2_identify(void) {
    if ((RS_CRYPTO_REG(RS_CRYPTO_REG_IP_ID) != RS_CRYPTO_IP_ID_VALUE) ||
        (RS_CRYPTO_REG(RS_CRYPTO_REG_IP_VERSION) != RS_CRYPTO_IP_VERSION_VALUE) ||
        (RS_CRYPTO_REG(RS_CRYPTO_REG_TABLE_ID) != RS_CRYPTO_TABLE_ID_VALUE) ||
        ((RS_CRYPTO_REG(RS_CRYPTO_REG_CAPABILITY0) & RS_CRYPTO_CAP_STORAGE_INIT) == 0U)) {
        return RS_ENOTSUP;
    }
    return RS_OK;
}

static uint32_t rs_crypto_table_word(uint32_t index) {
    uint32_t word = 0U;

    if (index < 528U) {
        word = rs_crypto_aes_constants[index];
    } else if ((index >= 1024U) && (index < 1104U)) {
        word = rs_crypto_sha_constants[index - 1024U];
    } else {
        /* All reserved words, including both banks' unused tails, are zero. */
    }
    return word;
}

static void rs_crypto_cancel_unlocked(void) {
    const uint32_t status = RS_CRYPTO_REG(RS_CRYPTO_REG_MEM_STATUS);

    if (((status & (RS_CRYPTO_MEM_STATUS_LOAD_ACTIVE | RS_CRYPTO_MEM_STATUS_VERIFY_BUSY)) != 0U) &&
        ((status & (RS_CRYPTO_MEM_STATUS_TABLE_LOCKED | RS_CRYPTO_MEM_STATUS_FAULT)) == 0U)) {
        if ((status & RS_CRYPTO_MEM_STATUS_VERIFY_BUSY) != 0U) {
            /* Verification can lock between this read and the next APB write.
             * ZEROIZE cancels our unlocked attempt or preserves a completed
             * image. No engine can start while this serialized init owns it.
             * Returning timeout does not certify the asynchronous scrub. */
            RS_CRYPTO_REG(RS_CRYPTO_REG_COMMAND) = RS_CRYPTO_COMMAND_ZEROIZE;
        } else {
            RS_CRYPTO_REG(RS_CRYPTO_REG_MEM_CONTROL) = RS_CRYPTO_MEM_CONTROL_CANCEL;
        }
    }
}

rs_status_t rs_crypto_init(rs_timeout_t timeout) {
    uint32_t status;
    uint32_t index;

    if (rs_crypto_v2_identify() != RS_OK) {
        return RS_ENOTSUP;
    }
    if ((RS_CRYPTO_REG(RS_CRYPTO_REG_STATUS) & RS_CRYPTO_ENGINE_BUSY_MASK) != 0U) {
        return RS_EIO;
    }
    status = RS_CRYPTO_REG(RS_CRYPTO_REG_MEM_STATUS);
    if ((status & (RS_CRYPTO_MEM_STATUS_LOAD_ACTIVE | RS_CRYPTO_MEM_STATUS_VERIFY_BUSY |
                   RS_CRYPTO_MEM_STATUS_FAULT)) != 0U) {
        return RS_EIO;
    }
    if ((status & RS_CRYPTO_IMAGE_READY_MASK) == RS_CRYPTO_IMAGE_READY_MASK) {
        return RS_OK;
    }
    while ((status & RS_CRYPTO_MEM_STATUS_SCRUB_BUSY) != 0U) {
        if (timeout == 0U) {
            return RS_ETIMEOUT;
        }
        --timeout;
        status = RS_CRYPTO_REG(RS_CRYPTO_REG_MEM_STATUS);
        if ((status & RS_CRYPTO_MEM_STATUS_FAULT) != 0U) {
            return RS_EIO;
        }
    }
    if ((status & RS_CRYPTO_IMAGE_READY_MASK) == RS_CRYPTO_IMAGE_READY_MASK) {
        return RS_OK;
    }
    if (timeout == 0U) {
        return RS_ETIMEOUT;
    }
    --timeout;
    RS_CRYPTO_REG(RS_CRYPTO_REG_MEM_CONTROL) = RS_CRYPTO_MEM_CONTROL_BEGIN;
    for (index = 0U; index < RS_CRYPTO_TABLE_WORD_COUNT; ++index) {
        if (timeout == 0U) {
            rs_crypto_cancel_unlocked();
            return RS_ETIMEOUT;
        }
        --timeout;
        status = RS_CRYPTO_REG(RS_CRYPTO_REG_MEM_STATUS);
        if ((status & (RS_CRYPTO_MEM_STATUS_FAULT | RS_CRYPTO_MEM_STATUS_LOAD_ACTIVE)) !=
            RS_CRYPTO_MEM_STATUS_LOAD_ACTIVE) {
            rs_crypto_cancel_unlocked();
            return RS_EIO;
        }
        RS_CRYPTO_REG(RS_CRYPTO_REG_TABLE_DATA) = rs_crypto_table_word(index);
    }
    if (timeout == 0U) {
        rs_crypto_cancel_unlocked();
        return RS_ETIMEOUT;
    }
    --timeout;
    if (RS_CRYPTO_REG(RS_CRYPTO_REG_TABLE_WORDS) != RS_CRYPTO_TABLE_WORD_COUNT) {
        rs_crypto_cancel_unlocked();
        return RS_EIO;
    }
    RS_CRYPTO_REG(RS_CRYPTO_REG_MEM_CONTROL) = RS_CRYPTO_MEM_CONTROL_COMMIT;
    while (timeout != 0U) {
        --timeout;
        status = RS_CRYPTO_REG(RS_CRYPTO_REG_MEM_STATUS);
        if ((status & RS_CRYPTO_MEM_STATUS_FAULT) != 0U) {
            return RS_EIO;
        }
        if ((status & RS_CRYPTO_IMAGE_READY_MASK) == RS_CRYPTO_IMAGE_READY_MASK) {
            return (RS_CRYPTO_REG(RS_CRYPTO_REG_TABLE_CRC) == RS_CRYPTO_TABLE_CRC_VALUE) ? RS_OK
                                                                                         : RS_EIO;
        }
        if ((status & RS_CRYPTO_MEM_STATUS_VERIFY_BUSY) == 0U) {
            return RS_EIO;
        }
    }
    rs_crypto_cancel_unlocked();
    return RS_ETIMEOUT;
}

rs_status_t rs_crypto_zeroize_wait(rs_timeout_t timeout) {
    uint32_t status;
    uint32_t aes_config;
    uint32_t sha_config;

    if (rs_crypto_v2_identify() != RS_OK) {
        return RS_ENOTSUP;
    }
    status = RS_CRYPTO_REG(RS_CRYPTO_REG_MEM_STATUS);
    if ((status & RS_CRYPTO_MEM_STATUS_FAULT) != 0U) {
        return RS_EIO;
    }
    /* Config registers are inaccessible before READY. With no READY no engine
     * can own a DMA operation; an existing scrub may be joined idempotently. */
    aes_config = 0U;
    sha_config = 0U;
    if ((status & RS_CRYPTO_MEM_STATUS_READY) != 0U) {
        aes_config = RS_CRYPTO_REG(RS_CRYPTO_REG_AES_CFG);
        sha_config = RS_CRYPTO_REG(RS_CRYPTO_REG_SHA_CFG);
    }
    status = RS_CRYPTO_REG(RS_CRYPTO_REG_STATUS);
    if ((((status & RS_CRYPTO_STATUS_AES_BUSY) != 0U) &&
         ((aes_config & RS_CRYPTO_AES_CFG_DMA) != 0U)) ||
        (((status & RS_CRYPTO_STATUS_SHA_BUSY) != 0U) &&
         ((sha_config & RS_CRYPTO_SHA_CFG_DMA) != 0U)) ||
        (((aes_config & RS_CRYPTO_AES_CFG_DMA) != 0U) &&
         ((RS_CRYPTO_REG(RS_CRYPTO_REG_AES_DATA_STATUS) & RS_CRYPTO_AES_DATA_OUTPUT_VALID) !=
          0U)) ||
        ((RS_CRYPTO_REG(RS_CRYPTO_REG_MEM_STATUS) & RS_CRYPTO_MEM_STATUS_FAULT) != 0U)) {
        return RS_EIO;
    }
    if (timeout == 0U) {
        return RS_ETIMEOUT;
    }
    --timeout;
    RS_CRYPTO_REG(RS_CRYPTO_REG_IRQ_STATE) = RS_CRYPTO_IRQ_ZEROIZED;
    RS_CRYPTO_REG(RS_CRYPTO_REG_COMMAND) = RS_CRYPTO_COMMAND_ZEROIZE;
    while (timeout != 0U) {
        --timeout;
        status = RS_CRYPTO_REG(RS_CRYPTO_REG_MEM_STATUS);
        if ((status & RS_CRYPTO_MEM_STATUS_FAULT) != 0U) {
            return RS_EIO;
        }
        if (((status & RS_CRYPTO_MEM_STATUS_SCRUB_BUSY) == 0U) &&
            ((RS_CRYPTO_REG(RS_CRYPTO_REG_IRQ_STATE) & RS_CRYPTO_IRQ_ZEROIZED) != 0U)) {
            return ((RS_CRYPTO_REG(RS_CRYPTO_REG_AES_KEY_STATUS) &
                     RS_CRYPTO_AES_KEY_STATUS_VALID) == 0U)
                       ? RS_OK
                       : RS_EIO;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_crypto_zeroize(void) {
    return rs_crypto_zeroize_wait(RS_TIMEOUT_DEFAULT);
}
