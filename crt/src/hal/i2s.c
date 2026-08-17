#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/i2s.h>
#include <retrosoc/lib/printf.h>

#define RS_I2S_CTRL_OFFSET         UINT32_C(0x000)
#define RS_I2S_COMMAND_OFFSET      UINT32_C(0x004)
#define RS_I2S_STATUS_OFFSET       UINT32_C(0x008)
#define RS_I2S_STREAM_CTRL_OFFSET  UINT32_C(0x00C)
#define RS_I2S_FORMAT_OFFSET       UINT32_C(0x010)
#define RS_I2S_CLK_DIV_OFFSET      UINT32_C(0x014)
#define RS_I2S_FIFO_TH_OFFSET      UINT32_C(0x018)
#define RS_I2S_INTR_STATE_OFFSET   UINT32_C(0x024)
#define RS_I2S_INTR_ENABLE_OFFSET  UINT32_C(0x028)
#define RS_I2S_INTR_STATUS_OFFSET  UINT32_C(0x02C)
#define RS_I2S_INTR_TEST_OFFSET    UINT32_C(0x030)
#define RS_I2S_VERSION_OFFSET      UINT32_C(0x0F8)
#define RS_I2S_CAPABILITY_OFFSET   UINT32_C(0x0FC)

#define RS_I2S_CTRL_ENABLE_MASK    UINT32_C(0x00000001)
#define RS_I2S_CTRL_TX_ENABLE_MASK UINT32_C(0x00000002)
#define RS_I2S_CTRL_RX_ENABLE_MASK UINT32_C(0x00000004)
#define RS_I2S_CTRL_LOOPBACK_MASK  UINT32_C(0x00000008)
#define RS_I2S_CTRL_CLK_PROG_MASK  UINT32_C(0x00000010)
#define RS_I2S_COMMAND_TX_FLUSH    UINT32_C(0x00000001)
#define RS_I2S_COMMAND_RX_FLUSH    UINT32_C(0x00000002)
#define RS_I2S_STATUS_LEVEL_MASK   UINT32_C(0x000000FF)

static volatile uint32_t *rs_i2s_register(uint32_t offset) {
    return (volatile uint32_t *)(RS_SOC_APB4_I2S_BASE + (uintptr_t)offset);
}

static bool rs_i2s_config_valid(const rs_i2s_config_t *config) {
    if ((config == NULL) || ((uint32_t)config->preset > (uint32_t)RS_I2S_PRESET_24B_96K))
        return false;
    if (config->lowbound > config->upbound)
        return false;
    return true;
}

rs_status_t rs_i2s_probe(uint32_t *version, uint32_t *capability) {
    if ((version == NULL) || (capability == NULL))
        return RS_EINVAL;
    *version = *rs_i2s_register(RS_I2S_VERSION_OFFSET);
    *capability = *rs_i2s_register(RS_I2S_CAPABILITY_OFFSET);
    return (*version == UINT32_C(0x00010000)) ? RS_OK : RS_EIO;
}

rs_status_t rs_i2s_configure(const rs_i2s_config_t *config) {
    uint32_t control;
    uint32_t format;
    uint32_t clock_div;

    if (!rs_i2s_config_valid(config))
        return RS_EINVAL;
    (void)rs_i2s_disable();
    format = (uint32_t)config->preset;
    if (config->bitmode_24)
        format |= UINT32_C(0x00000004);
    clock_div = (uint32_t)config->sclk_div | ((uint32_t)config->lrck_div << 8) |
                ((uint32_t)config->mclk_div << 16);
    control = (config->loopback ? RS_I2S_CTRL_LOOPBACK_MASK : 0U) |
              (config->clock_prog ? RS_I2S_CTRL_CLK_PROG_MASK : 0U);
    *rs_i2s_register(RS_I2S_FORMAT_OFFSET) = format;
    *rs_i2s_register(RS_I2S_CLK_DIV_OFFSET) = clock_div;
    *rs_i2s_register(RS_I2S_FIFO_TH_OFFSET) =
        (uint32_t)config->upbound | ((uint32_t)config->lowbound << 8);
    *rs_i2s_register(RS_I2S_STREAM_CTRL_OFFSET) =
        (config->stream_tx ? 1U : 0U) | (config->stream_rx ? 2U : 0U);
    *rs_i2s_register(RS_I2S_INTR_STATE_OFFSET) = RS_I2S_INTERRUPT_ALL;
    *rs_i2s_register(RS_I2S_CTRL_OFFSET) = control;
    return RS_OK;
}

rs_status_t rs_i2s_enable(bool tx, bool rx) {
    uint32_t control;

    control = *rs_i2s_register(RS_I2S_CTRL_OFFSET);
    control |= RS_I2S_CTRL_ENABLE_MASK;
    if (tx)
        control |= RS_I2S_CTRL_TX_ENABLE_MASK;
    else
        control &= ~RS_I2S_CTRL_TX_ENABLE_MASK;
    if (rx)
        control |= RS_I2S_CTRL_RX_ENABLE_MASK;
    else
        control &= ~RS_I2S_CTRL_RX_ENABLE_MASK;
    *rs_i2s_register(RS_I2S_CTRL_OFFSET) = control;
    return RS_OK;
}

rs_status_t rs_i2s_disable(void) {
    *rs_i2s_register(RS_I2S_CTRL_OFFSET) &=
        ~(RS_I2S_CTRL_ENABLE_MASK | RS_I2S_CTRL_TX_ENABLE_MASK | RS_I2S_CTRL_RX_ENABLE_MASK);
    return RS_OK;
}

rs_status_t rs_i2s_flush(bool tx, bool rx, rs_timeout_t timeout) {
    uint32_t command;
    uint32_t status;
    uint32_t busy_mask;

    command = (tx ? RS_I2S_COMMAND_TX_FLUSH : 0U) | (rx ? RS_I2S_COMMAND_RX_FLUSH : 0U);
    busy_mask = (tx ? RS_I2S_STATUS_TX_FLUSH_BUSY : 0U) | (rx ? RS_I2S_STATUS_RX_FLUSH_BUSY : 0U);
    if (command == 0U)
        return RS_EINVAL;
    *rs_i2s_register(RS_I2S_COMMAND_OFFSET) = command;
    while (timeout-- != 0U) {
        status = *rs_i2s_register(RS_I2S_STATUS_OFFSET);
        if ((status & busy_mask) == 0U)
            return RS_OK;
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_i2s_write(uint32_t word, rs_timeout_t timeout) {
    uint32_t status;

    while (timeout-- != 0U) {
        status = *rs_i2s_register(RS_I2S_STATUS_OFFSET);
        if ((status & RS_I2S_STATUS_TX_FULL) == 0U) {
            *(volatile uint32_t *)rs_i2s_txdata_address() = word;
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_i2s_read(uint32_t *word, rs_timeout_t timeout) {
    uint32_t status;

    if (word == NULL)
        return RS_EINVAL;
    while (timeout-- != 0U) {
        status = *rs_i2s_register(RS_I2S_STATUS_OFFSET);
        if ((status & RS_I2S_STATUS_RX_EMPTY) == 0U) {
            *word = *(volatile uint32_t *)rs_i2s_rxdata_address();
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

rs_status_t rs_i2s_get_status(rs_i2s_status_t *status) {
    if (status == NULL)
        return RS_EINVAL;
    status->status = *rs_i2s_register(RS_I2S_STATUS_OFFSET);
    status->tx_level = (uint8_t)((status->status >> 8) & RS_I2S_STATUS_LEVEL_MASK);
    status->rx_level = (uint8_t)((status->status >> 16) & RS_I2S_STATUS_LEVEL_MASK);
    status->interrupt_state = *rs_i2s_register(RS_I2S_INTR_STATE_OFFSET);
    status->enable = (status->status & RS_I2S_STATUS_ENABLE) != 0U;
    status->tx_full = (status->status & RS_I2S_STATUS_TX_FULL) != 0U;
    status->tx_empty = (status->status & RS_I2S_STATUS_TX_EMPTY) != 0U;
    status->rx_full = (status->status & RS_I2S_STATUS_RX_FULL) != 0U;
    status->rx_empty = (status->status & RS_I2S_STATUS_RX_EMPTY) != 0U;
    return RS_OK;
}

rs_status_t rs_i2s_interrupt_enable(uint32_t mask) {
    if ((mask & ~RS_I2S_INTERRUPT_ALL) != 0U)
        return RS_EINVAL;
    *rs_i2s_register(RS_I2S_INTR_ENABLE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_i2s_interrupt_clear(uint32_t mask) {
    if ((mask & ~RS_I2S_INTERRUPT_ALL) != 0U)
        return RS_EINVAL;
    *rs_i2s_register(RS_I2S_INTR_STATE_OFFSET) = mask;
    return RS_OK;
}

rs_status_t rs_i2s_interrupt_test(uint32_t mask) {
    if ((mask & ~RS_I2S_INTERRUPT_ALL) != 0U)
        return RS_EINVAL;
    *rs_i2s_register(RS_I2S_INTR_TEST_OFFSET) = mask;
    return RS_OK;
}

void ip_i2s_test(int argc, char **argv) {
    uint32_t version;
    uint32_t capability;

    (void)argc;
    (void)argv;
    printf("i2s test\n");
    if (rs_i2s_probe(&version, &capability) == RS_OK) {
        printf("i2s v%lx capability %lx\n", (unsigned long)version, (unsigned long)capability);
    } else {
        printf("i2s probe failed\n");
    }
}
