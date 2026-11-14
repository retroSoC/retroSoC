#include <stddef.h>

#include <retrosoc/core/soc.h>
#include <retrosoc/hal/ppalite.h>

#if defined(RS_SOC_HAS_PPALITE) && (RS_SOC_HAS_PPALITE != 0U)
#define RS_PPALITE_PRESENT 1
#endif

#ifdef RS_PPALITE_PRESENT
static void rs_ppalite_fence(void) {
#ifdef __riscv
    __asm__ volatile("fence rw, rw" ::: "memory");
#else
    __asm__ volatile("" ::: "memory");
#endif
}
#endif

#define RS_PPALITE_CAPABILITY_RAW        UINT32_C(0x00000100)
#define RS_PPALITE_CAPABILITY_PROCESS    UINT32_C(0x00000200)
#define RS_PPALITE_STATUS_STATE_MASK     UINT32_C(0x00000007)
#define RS_PPALITE_STATUS_OWNER          UINT32_C(0x00000100)
#define RS_PPALITE_STATUS_SOURCE_DONE    UINT32_C(0x00000800)
#define RS_PPALITE_STATUS_DMA_DONE       UINT32_C(0x00001000)
#define RS_PPALITE_STATUS_RESULT_VALID   UINT32_C(0x00002000)
#define RS_PPALITE_STATUS_SOURCE_QUIET   UINT32_C(0x00004000)
#define RS_PPALITE_STATUS_TRANSPORT_IDLE UINT32_C(0x00008000)

#if defined(RS_PPALITE_TEST_MMIO)
extern volatile uint32_t rs_ppalite_test_mmio[1024];
#define RS_PPALITE_REG(offset) rs_ppalite_test_mmio[(offset) / 4U]
#elif defined(RS_PPALITE_PRESENT)
#define RS_PPALITE_REG(offset) RS_SOC_REG32(RS_SOC_APB4_PPALITE_BASE, (offset))
#endif

#ifndef RS_SOC_DVP_DMA_BURST_BEATS
#define RS_SOC_DVP_DMA_BURST_BEATS 4U
#endif

#ifdef RS_PPALITE_PRESENT
static uint32_t rs_ppalite_command(uint32_t index) {
    return UINT32_C(1) << index;
}

static uint32_t rs_ppalite_step_code(uint8_t step) {
    return (step == 1U) ? 0U : ((step == 2U) ? 1U : 2U);
}

static rs_status_t rs_ppalite_register_config(const rs_ppalite_config_t *config, uint32_t *size,
                                              uint32_t *sampling, uint32_t *value) {
    uint32_t width;
    uint32_t height;

    if ((config == NULL) || (size == NULL) || (sampling == NULL) || (value == NULL)) {
        return RS_EINVAL;
    }
    if ((uint32_t)config->input_format > (uint32_t)RS_PPALITE_INPUT_VYUY) {
        return RS_ENOTSUP;
    }
    if (((uint32_t)config->input_format < (uint32_t)RS_PPALITE_INPUT_YUYV) &&
        (config->output_gray8 || (config->source.format != RS_DVP_FORMAT_RGB565))) {
        return RS_ENOTSUP;
    }
    if (((uint32_t)config->input_format >= (uint32_t)RS_PPALITE_INPUT_YUYV) &&
        (config->rgb_swap || (config->source.format != RS_DVP_FORMAT_YUV422))) {
        return RS_ENOTSUP;
    }
    if ((config->output_gray8 && config->output_byte_swap) || !config->source.snapshot ||
        !config->source.stream_enable || config->source.byte_swap || config->source.pixel_swap) {
        return RS_ENOTSUP;
    }
    width = config->source.crop_enable ? config->source.crop_width : config->source.frame_width;
    height = config->source.crop_enable ? config->source.crop_height : config->source.frame_height;
    if ((width == 0U) || (height == 0U) || (config->step_x == 0U) || (config->step_y == 0U) ||
        (config->step_x > 4U) || (config->step_y > 4U) || (config->step_x == 3U) ||
        (config->step_y == 3U) || (config->phase_x >= config->step_x) ||
        (config->phase_y >= config->step_y) || (config->phase_x >= width) ||
        (config->phase_y >= height)) {
        return RS_EINVAL;
    }
    *size = (height << 16U) | width;
    *sampling = rs_ppalite_step_code(config->step_x) |
                (rs_ppalite_step_code(config->step_y) << 2U) | ((uint32_t)config->phase_x << 8U) |
                ((uint32_t)config->phase_y << 16U);
    *value = (uint32_t)config->input_format | (config->output_gray8 ? UINT32_C(0x10) : 0U) |
             (config->rgb_swap ? UINT32_C(0x20) : 0U) |
             (config->output_byte_swap ? UINT32_C(0x40) : 0U);
    return RS_OK;
}
#endif

rs_status_t rs_ppalite_probe(rs_ppalite_info_t *info) {
    if (info == NULL) {
        return RS_EINVAL;
    }
#ifdef RS_PPALITE_PRESENT
    info->version = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_IP_VERSION);
    info->capability = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_CAPABILITY);
    info->buffer_capability = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_BUFFER_CAPABILITY);
    info->clock_hz = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_CLOCK_HZ);
    info->dma_binding = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_DMA_BINDING);
    if ((RS_PPALITE_REG(RS_PPALITE_ABI_APB4_IP_ID) != RS_PPALITE_ABI_APB4_ID_VALUE) ||
        (info->version != RS_PPALITE_ABI_APB4_VERSION_VALUE) ||
        (info->dma_binding != RS_PPALITE_ABI_APB4_DMA_BINDING_VALUE)) {
        return RS_EIO;
    }
    return RS_OK;
#else
    info->version = 0U;
    info->capability = 0U;
    info->buffer_capability = 0U;
    info->clock_hz = 0U;
    info->dma_binding = 0U;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_ppalite_configure(const rs_ppalite_config_t *config) {
#ifdef RS_PPALITE_PRESENT
    rs_ppalite_info_t info;
    uint32_t size;
    uint32_t sampling;
    uint32_t value;
    rs_status_t result = rs_ppalite_register_config(config, &size, &sampling, &value);
    if (result != RS_OK) {
        return result;
    }
    result = rs_ppalite_probe(&info);
    if (result != RS_OK) {
        return result;
    }
    if ((info.capability & RS_PPALITE_CAPABILITY_PROCESS) == 0U) {
        return RS_ENOTSUP;
    }
    RS_PPALITE_REG(RS_PPALITE_ABI_APB4_CONFIG) = value;
    RS_PPALITE_REG(RS_PPALITE_ABI_APB4_INPUT_SIZE) = size;
    RS_PPALITE_REG(RS_PPALITE_ABI_APB4_SAMPLING) = sampling;
    return RS_OK;
#else
    (void)config;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_ppalite_select_route(rs_ppalite_route_t route, rs_timeout_t timeout) {
#ifdef RS_PPALITE_PRESENT
    rs_ppalite_info_t info;
    const rs_status_t result = rs_ppalite_probe(&info);
    if (result != RS_OK) {
        return result;
    }
    if (((uint32_t)route > (uint32_t)RS_PPALITE_ROUTE_PROCESS) ||
        ((route == RS_PPALITE_ROUTE_PROCESS) &&
         ((info.capability & RS_PPALITE_CAPABILITY_PROCESS) == 0U)) ||
        ((route == RS_PPALITE_ROUTE_RAW) &&
         ((info.capability & RS_PPALITE_CAPABILITY_RAW) == 0U))) {
        return RS_ENOTSUP;
    }
    RS_PPALITE_REG(RS_PPALITE_ABI_APB4_ROUTE) = (uint32_t)route;
    while (timeout-- != 0U) {
        if (RS_PPALITE_REG(RS_PPALITE_ABI_APB4_ROUTE) == (uint32_t)route) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
#else
    (void)route;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_ppalite_get_status(rs_ppalite_status_t *status) {
    if (status == NULL) {
        return RS_EINVAL;
    }
#ifdef RS_PPALITE_PRESENT
    status->status = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_STATUS);
    status->irq_state = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_IRQ_STATE);
    status->first_error = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_FIRST_ERROR);
    status->source_error = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_SOURCE_ERROR);
    status->dma_error = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_DMA_ERROR);
    status->owned = (status->status & RS_PPALITE_STATUS_OWNER) != 0U;
    status->result_valid = (status->status & RS_PPALITE_STATUS_RESULT_VALID) != 0U;
    return RS_OK;
#else
    status->status = 0U;
    status->irq_state = 0U;
    status->first_error = 0U;
    status->source_error = 0U;
    status->dma_error = 0U;
    status->owned = false;
    status->result_valid = false;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_ppalite_get_measurements(rs_ppalite_measurements_t *measurements) {
    if (measurements == NULL) {
        return RS_EINVAL;
    }
#ifdef RS_PPALITE_PRESENT
    measurements->input_words = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_INPUT_WORDS);
    measurements->input_pixels = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_INPUT_PIXELS);
    measurements->input_lines = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_INPUT_LINES);
    measurements->output_words = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_OUTPUT_WORDS);
    measurements->output_lines = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_OUTPUT_LINES);
    measurements->input_stall_cycles = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_INPUT_STALL_CYCLES);
    measurements->output_stall_cycles = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_OUTPUT_STALL_CYCLES);
    measurements->fifo_levels = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_FIFO_LEVELS);
    return RS_OK;
#else
    *measurements = (rs_ppalite_measurements_t){0};
    return RS_ENOTSUP;
#endif
}

#ifdef RS_PPALITE_PRESENT
static rs_status_t rs_ppalite_wait_state(uint32_t expected, rs_timeout_t timeout) {
    while (timeout-- != 0U) {
        const uint32_t status = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_STATUS);
        if ((status & RS_PPALITE_STATUS_STATE_MASK) == expected) {
            return RS_OK;
        }
        if ((status & RS_PPALITE_STATUS_STATE_MASK) == RS_PPALITE_ABI_STATE_CLOSING) {
            return RS_EIO;
        }
    }
    return RS_ETIMEOUT;
}

static rs_status_t rs_ppalite_wait_quiet(rs_timeout_t timeout, bool require_processor_idle) {
    const uint32_t required = RS_PPALITE_STATUS_SOURCE_QUIET | RS_PPALITE_STATUS_TRANSPORT_IDLE;
    while (timeout-- != 0U) {
        const uint32_t status = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_STATUS);
        const uint32_t levels = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_FIFO_LEVELS);
        if (((status & required) == required) &&
            (!require_processor_idle || ((levels & UINT32_C(0xF3)) == 0U))) {
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
}

static rs_status_t rs_ppalite_reset_dma(rs_ppalite_session_t *session, rs_timeout_t timeout) {
    rs_status_t result = rs_dma_session_abort_wait(&session->dma_session, timeout);
    if (result == RS_OK) {
        result = rs_dma_session_reset(&session->dma_session);
    }
    return result;
}
#endif

rs_status_t rs_ppalite_capture_begin(rs_ppalite_session_t *session,
                                     const rs_ppalite_config_t *config, uintptr_t destination,
                                     uint32_t capacity_bytes, rs_timeout_t timeout) {
#ifdef RS_PPALITE_PRESENT
    rs_ppalite_info_t info;
    rs_ppalite_layout_t layout;
    rs_ppalite_session_t fresh = {0};
    rs_dma_config_t dma_config = {0};
    rs_status_t result;
    uint32_t status;

    if ((session == NULL) || (config == NULL) || (timeout == 0U)) {
        return RS_EINVAL;
    }
    if (session->acquired) {
        return RS_EBUSY;
    }
    result = rs_ppalite_layout(config, destination, capacity_bytes, &layout);
    if (result != RS_OK) {
        return result;
    }
    result = rs_ppalite_probe(&info);
    if (result != RS_OK) {
        return result;
    }
    if (((info.capability & RS_PPALITE_CAPABILITY_PROCESS) == 0U) ||
        (RS_DMA_REG(RS_DMA_REG_IP_VERSION) < RS_DMA_IP_VERSION_V22) ||
        (rs_dma_supports_request(RS_DMA_REQUEST_DVP_RX) != RS_OK)) {
        return RS_ENOTSUP;
    }
    if (RS_PPALITE_REG(RS_PPALITE_ABI_APB4_ROUTE) != RS_PPALITE_ROUTE_PROCESS) {
        return RS_ENOTSUP;
    }
    result = rs_dvp_configure(&config->source);
    if (result != RS_OK) {
        return result;
    }
    fresh.config = *config;
    fresh.layout = layout;
    fresh.destination = destination;
    fresh.capacity_bytes = capacity_bytes;
    *session = fresh;
    result = rs_dma_session_acquire(&session->dma_session, RS_DMA_CHANNEL_DVP);
    if (result != RS_OK) {
        return RS_EBUSY;
    }
    session->acquired = true;
    dma_config.kind = RS_DMA_KIND_STREAM_TO_MM;
    dma_config.request = RS_DMA_REQUEST_DVP_RX;
    dma_config.source = (uintptr_t)0U;
    dma_config.destination = destination;
    dma_config.byte_count = layout.transport_bytes;
    dma_config.width = RS_DMA_WIDTH_32;
    dma_config.source_increment = false;
    dma_config.destination_increment = true;
    dma_config.priority = 3U;
    dma_config.burst_beats = RS_SOC_DVP_DMA_BURST_BEATS;
    result = rs_dma_session_configure(&session->dma_session, &dma_config);
    if (result == RS_OK) {
        result = rs_ppalite_configure(config);
    }
    if (result == RS_OK) {
        RS_PPALITE_REG(RS_PPALITE_ABI_APB4_DESTINATION) = (uint32_t)destination;
        RS_PPALITE_REG(RS_PPALITE_ABI_APB4_CAPACITY_BYTES) = capacity_bytes;
        result = rs_ppalite_wait_quiet(timeout, true);
    }
    if (result == RS_OK) {
        RS_PPALITE_REG(RS_PPALITE_ABI_APB4_COMMAND) =
            rs_ppalite_command(RS_PPALITE_ABI_COMMAND_ARM);
        result = rs_ppalite_wait_state(RS_PPALITE_ABI_STATE_ARMED, timeout);
    }
    status = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_STATUS);
    if ((result != RS_OK) && ((status & RS_PPALITE_STATUS_OWNER) == 0U)) {
        rs_status_t cleanup_result = rs_ppalite_reset_dma(session, timeout);
        if (cleanup_result == RS_OK) {
            cleanup_result = rs_dma_session_release(&session->dma_session);
        }
        if (cleanup_result == RS_OK) {
            session->acquired = false;
            session->started = false;
            session->stop_requested = false;
            session->finalized = false;
        } else {
            result = cleanup_result;
        }
    }
    return result;
#else
    (void)session;
    (void)config;
    (void)destination;
    (void)capacity_bytes;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_ppalite_capture_start(rs_ppalite_session_t *session, rs_timeout_t timeout) {
#ifdef RS_PPALITE_PRESENT
    rs_status_t result;
    if ((session == NULL) || !session->acquired || session->started || (timeout == 0U)) {
        return RS_EINVAL;
    }
    if ((RS_PPALITE_REG(RS_PPALITE_ABI_APB4_STATUS) & RS_PPALITE_STATUS_STATE_MASK) !=
        RS_PPALITE_ABI_STATE_ARMED) {
        return RS_EIO;
    }
    result = rs_dma_session_start(&session->dma_session);
    if (result != RS_OK) {
        return result;
    }
    session->started = true;
    result = rs_dvp_start_with_timeout(timeout);
    if (result != RS_OK) {
        (void)rs_ppalite_abort(session, timeout);
    }
    return result;
#else
    (void)session;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_ppalite_capture_wait(rs_ppalite_session_t *session, rs_ppalite_frame_t *frame,
                                    rs_timeout_t timeout) {
#ifdef RS_PPALITE_PRESENT
    rs_dma_status_t dma_status;
    rs_dvp_status_t source_status;
    uint32_t status;
    uint32_t output_size;
    rs_status_t result;

    if ((session == NULL) || (frame == NULL) || !session->acquired || !session->started ||
        (timeout == 0U)) {
        return RS_EINVAL;
    }
    while (timeout-- != 0U) {
        status = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_STATUS);
        if ((status & RS_PPALITE_STATUS_STATE_MASK) == RS_PPALITE_ABI_STATE_CLOSING) {
            return RS_EIO;
        }
        if (((status & RS_PPALITE_STATUS_SOURCE_DONE) != 0U) && !session->stop_requested) {
            result = rs_dvp_stop(timeout);
            if (result != RS_OK) {
                (void)rs_ppalite_abort(session, timeout);
                return result;
            }
            session->stop_requested = true;
        }
        if (((status & RS_PPALITE_STATUS_STATE_MASK) == RS_PPALITE_ABI_STATE_VERIFY) &&
            ((status & RS_PPALITE_STATUS_SOURCE_DONE) != 0U) &&
            ((status & RS_PPALITE_STATUS_DMA_DONE) != 0U) &&
            ((status & RS_PPALITE_STATUS_TRANSPORT_IDLE) != 0U) &&
            ((status & RS_PPALITE_STATUS_SOURCE_QUIET) != 0U) && session->stop_requested) {
            if ((rs_dvp_get_status(&source_status) != RS_OK) ||
                (source_status.error_status != 0U)) {
                (void)rs_ppalite_abort(session, timeout);
                return RS_EIO;
            }
            result = rs_dma_get_status(RS_DMA_CHANNEL_DVP, &dma_status);
            if ((result != RS_OK) || dma_status.busy || dma_status.error || dma_status.aborted ||
                !dma_status.done || (dma_status.remaining != 0U) ||
                (dma_status.bytes_done != session->layout.transport_bytes)) {
                (void)rs_ppalite_abort(session, timeout);
                return RS_EIO;
            }
            rs_ppalite_fence();
            RS_PPALITE_REG(RS_PPALITE_ABI_APB4_COMMAND) =
                rs_ppalite_command(RS_PPALITE_ABI_COMMAND_FINALIZE);
            result = rs_ppalite_wait_state(RS_PPALITE_ABI_STATE_COMPLETE, timeout);
            if (result != RS_OK) {
                return result;
            }
            status = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_STATUS);
            if (((status & RS_PPALITE_STATUS_RESULT_VALID) == 0U) ||
                (RS_PPALITE_REG(RS_PPALITE_ABI_APB4_FIRST_ERROR) != 0U)) {
                return RS_EIO;
            }
            output_size = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_OUTPUT_SIZE);
            frame->base = session->destination;
            frame->capacity_bytes = session->capacity_bytes;
            frame->width = (uint16_t)(output_size & UINT32_C(0xFFFF));
            frame->height = (uint16_t)(output_size >> 16U);
            frame->input_format = session->config.input_format;
            frame->result_config = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_RESULT_CONFIG);
            frame->row_bytes = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_ROW_BYTES);
            frame->stride_bytes = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_STRIDE_BYTES);
            frame->valid_bytes = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_VALID_BYTES);
            frame->transport_bytes = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_TRANSPORT_BYTES);
            frame->job_sequence = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_JOB_SEQUENCE);
            frame->source_sequence = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_SOURCE_SEQUENCE);
            frame->error_status = 0U;
            frame->output_byte_swap = session->config.output_byte_swap;
            frame->valid = true;
            session->finalized = true;
            return RS_OK;
        }
    }
    return RS_ETIMEOUT;
#else
    (void)session;
    (void)frame;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_ppalite_abort(rs_ppalite_session_t *session, rs_timeout_t timeout) {
#ifdef RS_PPALITE_PRESENT
    rs_status_t result;
    if ((session == NULL) || !session->acquired || (timeout == 0U)) {
        return RS_EINVAL;
    }
    if ((RS_PPALITE_REG(RS_PPALITE_ABI_APB4_STATUS) & RS_PPALITE_STATUS_OWNER) != 0U) {
        RS_PPALITE_REG(RS_PPALITE_ABI_APB4_COMMAND) =
            rs_ppalite_command(RS_PPALITE_ABI_COMMAND_ABORT);
    }
    session->finalized = false;
    result = rs_dma_session_abort_wait(&session->dma_session, timeout);
    return result;
#else
    (void)session;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_ppalite_recover(rs_ppalite_session_t *session, rs_timeout_t timeout) {
#ifdef RS_PPALITE_PRESENT
    rs_dvp_status_t source_status;
    rs_status_t result;
    uint32_t status;
    bool closing;
    if ((session == NULL) || !session->acquired || (timeout == 0U)) {
        return RS_EINVAL;
    }
    status = RS_PPALITE_REG(RS_PPALITE_ABI_APB4_STATUS);
    closing = (status & RS_PPALITE_STATUS_STATE_MASK) == RS_PPALITE_ABI_STATE_CLOSING;
    if (!closing && (((status & RS_PPALITE_STATUS_STATE_MASK) != RS_PPALITE_ABI_STATE_IDLE) ||
                     ((status & RS_PPALITE_STATUS_OWNER) != 0U))) {
        return RS_EIO;
    }
    result = rs_ppalite_reset_dma(session, timeout);
    if ((result == RS_OK) && closing) {
        result = rs_dvp_abort();
    }
    if ((result == RS_OK) && closing) {
        result = rs_dvp_flush();
    }
    if ((result == RS_OK) && closing && (rs_dvp_get_status(&source_status) != RS_OK)) {
        result = RS_EIO;
    }
    if (result == RS_OK) {
        result = rs_ppalite_wait_quiet(timeout, false);
    }
    if (result != RS_OK) {
        return result;
    }
    if (closing) {
        RS_PPALITE_REG(RS_PPALITE_ABI_APB4_COMMAND) =
            rs_ppalite_command(RS_PPALITE_ABI_COMMAND_RECOVER);
        result = rs_ppalite_wait_state(RS_PPALITE_ABI_STATE_IDLE, timeout);
        if (result != RS_OK) {
            return result;
        }
    }
    if ((RS_PPALITE_REG(RS_PPALITE_ABI_APB4_STATUS) & RS_PPALITE_STATUS_OWNER) != 0U) {
        return RS_EIO;
    }
    result = rs_dma_session_release(&session->dma_session);
    if (result == RS_OK) {
        session->acquired = false;
        session->started = false;
        session->stop_requested = false;
        session->finalized = false;
    }
    return result;
#else
    (void)session;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}

rs_status_t rs_ppalite_release(rs_ppalite_session_t *session, rs_timeout_t timeout) {
#ifdef RS_PPALITE_PRESENT
    rs_status_t result;
    if ((session == NULL) || !session->acquired || !session->finalized || (timeout == 0U)) {
        return RS_EINVAL;
    }
    RS_PPALITE_REG(RS_PPALITE_ABI_APB4_COMMAND) =
        rs_ppalite_command(RS_PPALITE_ABI_COMMAND_RELEASE);
    result = rs_ppalite_wait_state(RS_PPALITE_ABI_STATE_IDLE, timeout);
    if (result != RS_OK) {
        return result;
    }
    if ((RS_PPALITE_REG(RS_PPALITE_ABI_APB4_STATUS) &
         (RS_PPALITE_STATUS_OWNER | RS_PPALITE_STATUS_RESULT_VALID)) !=
        RS_PPALITE_STATUS_RESULT_VALID) {
        return RS_EIO;
    }
    rs_ppalite_fence();
    result = rs_dma_session_release(&session->dma_session);
    if (result == RS_OK) {
        session->acquired = false;
        session->started = false;
        session->stop_requested = false;
        session->finalized = false;
    }
    return result;
#else
    (void)session;
    (void)timeout;
    return RS_ENOTSUP;
#endif
}
