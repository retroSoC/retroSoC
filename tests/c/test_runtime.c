#include <stddef.h>
#include <stdint.h>

#include <retrosoc/core/status.h>
#include <retrosoc/core/wait.h>
#include <retrosoc/hal/lcd.h>
#include <retrosoc/hal/spisd.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/lib/stdlib.h>
#include <retrosoc/lib/string.h>
#include <retrosoc/media/video_player.h>
#include <retrosoc/media/wav_audio.h>

#define TEST_STORAGE_ADDRESS ((uintptr_t)0x1000U)

int __clzsi2(unsigned int value);
long long __divdi3(long long dividend, long long divisor);
int __ffssi2(unsigned int value);
unsigned long long __udivdi3(unsigned long long dividend, unsigned long long divisor);
unsigned long long __umoddi3(unsigned long long dividend, unsigned long long divisor);

static uint8_t storage[32];
static uint32_t image_call_count;

void putch(char ch)
{
    (void)ch;
}

void lcd_fill_image(uint16_t x_start,
                    uint16_t y_start,
                    uint16_t x_end,
                    uint16_t y_end,
                    uint32_t *data)
{
    (void)x_start;
    (void)y_start;
    (void)x_end;
    (void)y_end;
    (void)data;
    ++image_call_count;
}

rs_status_t rs_spisd_read_bytes(void *buffer, size_t byte_count, uintptr_t address)
{
    size_t offset;

    if ((buffer == NULL) || (address < TEST_STORAGE_ADDRESS)) {
        return RS_EINVAL;
    }
    offset = (size_t)(address - TEST_STORAGE_ADDRESS);
    if (byte_count > (sizeof(storage) - offset)) {
        return RS_EIO;
    }
    for (size_t index = 0U; index < byte_count; ++index) {
        ((uint8_t *)buffer)[index] = storage[offset + index];
    }
    return RS_OK;
}

static rs_status_t test_reader_read(void *context,
                                    uint32_t offset,
                                    void *buffer,
                                    size_t byte_count)
{
    const uint8_t *bytes = context;

    if ((bytes == NULL) || (buffer == NULL)) {
        return RS_EINVAL;
    }
    for (size_t index = 0U; index < byte_count; ++index) {
        ((uint8_t *)buffer)[index] = bytes[offset + index];
    }
    return RS_OK;
}

static int test_string_helpers(void)
{
    char buffer[8] = {'x', '\0'};
    int32_t value;

    if (strncpy(buffer, "z", 0U) != buffer || buffer[0] != 'x') {
        return 1;
    }
    if (strncmp("left", "right", 0U) != 0) {
        return 2;
    }
    if (rs_strlcpy(buffer, "abcdefghi", sizeof(buffer)) != 9U ||
        strcmp(buffer, "abcdefg") != 0) {
        return 3;
    }
    if (rs_strlcat(buffer, "x", sizeof(buffer)) != 8U ||
        strcmp(buffer, "abcdefg") != 0) {
        return 4;
    }
    if (rs_strtoi32("-2147483648", &value) != RS_OK || value != INT32_MIN ||
        rs_strtoi32("2147483648", &value) != RS_EFORMAT ||
        rs_strtoi32("12x", &value) != RS_EFORMAT) {
        return 5;
    }
    return 0;
}

static int test_formatter(void)
{
    char buffer[32];

    if (rs_snprintf(buffer, sizeof(buffer), "%#08x:%lld:%zu", 0x2AU, -42LL,
                    (size_t)7U) != 14 || strcmp(buffer, "0x00002a:-42:7") != 0) {
        return 1;
    }
    if (rs_snprintf(buffer, 4U, "abcdef") != 6 || strcmp(buffer, "abc") != 0) {
        return 2;
    }
    if (rs_snprintf(NULL, 0U, "value=%llu", UINT64_MAX) != 26) {
        return 3;
    }
    if (rs_snprintf(buffer, sizeof(buffer), "%p", (void *)(uintptr_t)0x1234U) != 6 ||
        strcmp(buffer, "0x1234") != 0) {
        return 4;
    }
    return 0;
}

static int test_compiler_helpers(void)
{
    if ((__clzsi2(0U) != 32) || (__clzsi2(1U) != 31) || (__ffssi2(0U) != 0) ||
        (__ffssi2(1U) != 1) || (__ffssi2(0x10U) != 5)) {
        return 1;
    }
    if ((__udivdi3(UINT64_MAX, 3U) != 6148914691236517205ULL) ||
        (__umoddi3(UINT64_MAX, 3U) != 0U) ||
        (__udivdi3(UINT64_MAX, UINT64_MAX) != 1U) ||
        (__umoddi3(100U, 7U) != 2U) || (__divdi3(-100LL, 7LL) != -14LL)) {
        return 2;
    }
    return 0;
}

static int test_wait_helper(void)
{
    volatile uint32_t value = 0x30U;

    if (rs_wait_mask(&value, 0x30U, 0x30U, 1U) != RS_OK ||
        rs_wait_mask(&value, 0x40U, 0x40U, 1U) != RS_ETIMEOUT ||
        rs_wait_mask(NULL, 1U, 1U, 1U) != RS_EINVAL ||
        rs_wait_value(&value, 0x30U, 1U) != RS_OK ||
        rs_wait_not_value(&value, 0U, 1U) != RS_OK ||
        rs_wait_not_value(&value, 0x30U, 1U) != RS_ETIMEOUT) {
        return 1;
    }
    return 0;
}

static int test_wav_parser(void)
{
    static const uint8_t wav[] = {
        'R', 'I', 'F', 'F', 40U, 0U, 0U, 0U, 'W', 'A', 'V', 'E',
        'f', 'm', 't', ' ', 16U, 0U, 0U, 0U, 1U, 0U, 1U, 0U,
        0x40U, 0x1FU, 0U, 0U, 0x80U, 0x3EU, 0U, 0U, 2U, 0U, 16U, 0U,
        'd', 'a', 't', 'a', 4U, 0U, 0U, 0U, 0U, 1U, 2U, 3U,
    };
    rs_wav_info_t info;
    const rs_wav_reader_t reader = {test_reader_read, (void *)wav, sizeof(wav)};

    if (rs_wav_parse(&reader, &info) != RS_OK || info.sample_rate != 8000U ||
        info.block_align != 2U || info.data_offset != 44U || info.data_size != 4U) {
        return 1;
    }
    if (rs_wav_parse(&(rs_wav_reader_t){test_reader_read, (void *)wav, 12U}, &info) !=
        RS_EFORMAT) {
        return 2;
    }
    return 0;
}

static int test_video_parser(void)
{
    rs_video_info_t info;

    (void)memset(storage, 0, sizeof(storage));
    storage[0] = 2U;
    storage[4] = 2U;
    storage[8] = 1U;
    if (rs_video_parse(storage, 24U, &info) != RS_OK || info.frame_size != 8U ||
        rs_video_parse(storage, 16U, &info) != RS_EFORMAT) {
        return 1;
    }
    image_call_count = 0U;
    if (rs_video_show_spisd(TEST_STORAGE_ADDRESS, 24U) != RS_OK || image_call_count != 1U) {
        return 2;
    }
    return 0;
}

int main(void)
{
    const int results[] = {
        test_string_helpers(),
        test_formatter(),
        test_compiler_helpers(),
        test_wait_helper(),
        test_wav_parser(),
        test_video_parser(),
    };

    for (size_t index = 0U; index < (sizeof(results) / sizeof(results[0])); ++index) {
        if (results[index] != 0) {
            return (int)(index + 1U);
        }
    }
    return 0;
}
