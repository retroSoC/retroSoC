#include <retrosoc/hal/rng.h>
#include <retrosoc/core/soc.h>
#include <retrosoc/lib/printf.h>

static rs_status_t rs_rng_status(rng_status_t status) {
    rs_status_t result;

    switch (status) {
    case RNG_STATUS_OK:
        result = RS_OK;
        break;
    case RNG_STATUS_INVALID_ARGUMENT:
        result = RS_EINVAL;
        break;
    case RNG_STATUS_TIMEOUT:
        result = RS_ETIMEOUT;
        break;
    case RNG_STATUS_UNAVAILABLE:
    case RNG_STATUS_UNQUALIFIED:
        result = RS_ENOTSUP;
        break;
    case RNG_STATUS_HEALTH_FAILURE:
        result = RS_EIO;
        break;
    case RNG_STATUS_INCOMPATIBLE:
    default:
        result = RS_EFORMAT;
        break;
    }

    return result;
}

rs_status_t rs_rng_init(const rs_rng_config_t *config) {
    return rs_rng_status(rng_init((uintptr_t)RS_SOC_APB4_RNG_BASE, config));
}

rs_status_t rs_rng_get_status(rs_rng_snapshot_t *snapshot) {
    return rs_rng_status(rng_get_status((uintptr_t)RS_SOC_APB4_RNG_BASE, snapshot));
}

rs_status_t rs_rng_read_entropy(uint32_t *word, rs_timeout_t timeout) {
    return rs_rng_status(rng_read_entropy((uintptr_t)RS_SOC_APB4_RNG_BASE, word, timeout));
}

rs_status_t rs_rng_read_diagnostic(uint32_t *word, rs_timeout_t timeout) {
    return rs_rng_status(rng_read_diagnostic((uintptr_t)RS_SOC_APB4_RNG_BASE, word, timeout));
}

rs_status_t rs_rng_recover(void) {
    return rs_rng_status(rng_recover((uintptr_t)RS_SOC_APB4_RNG_BASE));
}

rs_status_t rs_rng_interrupt_enable(uint32_t mask) {
    return rs_rng_status(rng_interrupt_enable((uintptr_t)RS_SOC_APB4_RNG_BASE, mask));
}

rs_status_t rs_rng_interrupt_clear(uint32_t mask) {
    return rs_rng_status(rng_interrupt_clear((uintptr_t)RS_SOC_APB4_RNG_BASE, mask));
}

rs_status_t rs_rng_interrupt_test(uint32_t mask) {
    return rs_rng_status(rng_interrupt_test((uintptr_t)RS_SOC_APB4_RNG_BASE, mask));
}

void rs_rng_shell_test(int argc, char **argv) {
    const rs_rng_config_t config = {
        .fifo_watermark = 1U,
        .interrupt_enable = 0U,
        .lock_config = true,
    };
    rs_rng_snapshot_t snapshot;
    uint32_t word;
    rs_status_t status;

    (void)argc;
    (void)argv;

    status = rs_rng_init(&config);
    if (status != RS_OK) {
        printf("[RNG] initialization failed: %d\n", status);
        return;
    }

    printf("[APB IP] RNG V2 diagnostic source\n");
    for (uint32_t index = 0U; index < 5U; ++index) {
        status = rs_rng_read_diagnostic(&word, RS_TIMEOUT_DEFAULT);
        if (status != RS_OK) {
            printf("[RNG] diagnostic read failed: %d\n", status);
            return;
        }
        printf("[RNG diagnostic] %x\n", word);
    }

    status = rs_rng_get_status(&snapshot);
    if (status != RS_OK) {
        printf("[RNG] status read failed: %d\n", status);
        return;
    }
    printf("[RNG status] qualified=%u level=%u errors=%x accepted=%u discarded=%u\n",
           snapshot.source_qualified ? 1U : 0U, (uint32_t)snapshot.fifo_level,
           snapshot.error_status, snapshot.accepted_count, snapshot.discard_count);

    status = rs_rng_read_entropy(&word, RS_TIMEOUT_DEFAULT);
    if (status == RS_ENOTSUP) {
        printf("[RNG] security entropy unavailable: integration source is unqualified\n");
    } else {
        printf("[RNG] unexpected entropy status: %d\n", status);
    }
}
