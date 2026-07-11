#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <stddef.h>

#include <retrosoc/lib/console.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/lib/string.h>
#include <retrosoc/hal/uart.h>

typedef enum {
    RS_FMT_NONE,
    RS_FMT_HH,
    RS_FMT_H,
    RS_FMT_L,
    RS_FMT_LL,
    RS_FMT_Z,
} rs_format_length_t;

typedef void (*rs_format_sink_t)(void *context, char value);

typedef struct {
    char *dst;
    size_t dst_size;
    size_t count;
    rs_format_sink_t sink;
    void *context;
} rs_format_output_t;

static void rs_format_putc(rs_format_output_t *output, char value) {
    if (output->sink != NULL) {
        output->sink(output->context, value);
    } else if ((output->dst != NULL) && (output->dst_size > 0U) &&
               (output->count < (output->dst_size - 1U))) {
        output->dst[output->count] = value;
    }
    ++output->count;
}

static void rs_format_repeat(rs_format_output_t *output, char value, size_t count) {
    while (count-- != 0U) {
        rs_format_putc(output, value);
    }
}

static size_t rs_format_uint(char *dst, uint64_t value, uint32_t base, bool uppercase) {
    static const char lower_digits[] = "0123456789abcdef";
    static const char upper_digits[] = "0123456789ABCDEF";
    const char *digits = uppercase ? upper_digits : lower_digits;
    char reversed[32];
    size_t count = 0U;
    size_t index;

    do {
        reversed[count] = digits[value % base];
        ++count;
        value /= base;
    } while (value != 0U);

    for (index = 0U; index < count; ++index) {
        dst[index] = reversed[count - index - 1U];
    }
    return count;
}

static uint64_t rs_format_unsigned_arg(va_list *args, rs_format_length_t length) {
    switch (length) {
    case RS_FMT_HH:
        return (uint64_t)(unsigned char)va_arg(*args, unsigned int);
    case RS_FMT_H:
        return (uint64_t)(unsigned short)va_arg(*args, unsigned int);
    case RS_FMT_L:
        return (uint64_t)va_arg(*args, unsigned long);
    case RS_FMT_LL:
        return (uint64_t)va_arg(*args, unsigned long long);
    case RS_FMT_Z:
        return (uint64_t)va_arg(*args, size_t);
    case RS_FMT_NONE:
    default:
        return (uint64_t)va_arg(*args, unsigned int);
    }
}

static int64_t rs_format_signed_arg(va_list *args, rs_format_length_t length) {
    switch (length) {
    case RS_FMT_HH:
        return (int64_t)(signed char)va_arg(*args, int);
    case RS_FMT_H:
        return (int64_t)(short)va_arg(*args, int);
    case RS_FMT_L:
        return (int64_t)va_arg(*args, long);
    case RS_FMT_LL:
        return (int64_t)va_arg(*args, long long);
    case RS_FMT_Z:
        return (int64_t)va_arg(*args, ptrdiff_t);
    case RS_FMT_NONE:
    default:
        return (int64_t)va_arg(*args, int);
    }
}

static void rs_format_number(rs_format_output_t *output, uint64_t value, bool negative,
                             uint32_t base, bool uppercase, bool left_align, bool zero_pad,
                             bool force_sign, bool space_sign, size_t width, size_t precision,
                             bool has_precision, bool alternate) {
    char digits[32];
    char prefix[2] = {'\0', '\0'};
    size_t digit_count = rs_format_uint(digits, value, base, uppercase);
    size_t prefix_count = 0U;
    size_t sign_count = 0U;
    size_t zero_count;
    size_t padding;
    char sign = '\0';

    if (has_precision && (precision == 0U) && (value == 0U)) {
        digit_count = 0U;
    }
    if (negative) {
        sign = '-';
        sign_count = 1U;
    } else if (force_sign) {
        sign = '+';
        sign_count = 1U;
    } else if (space_sign) {
        sign = ' ';
        sign_count = 1U;
    }
    if (alternate && (value != 0U) && (base == 16U)) {
        prefix[0] = '0';
        prefix[1] = uppercase ? 'X' : 'x';
        prefix_count = 2U;
    } else if (alternate && (value != 0U) && (base == 8U)) {
        prefix[0] = '0';
        prefix_count = 1U;
    }

    zero_count = (has_precision && (precision > digit_count)) ? precision - digit_count : 0U;
    padding = width > (sign_count + prefix_count + zero_count + digit_count)
                  ? width - sign_count - prefix_count - zero_count - digit_count
                  : 0U;

    if (!left_align && !(zero_pad && !has_precision)) {
        rs_format_repeat(output, ' ', padding);
    }
    if (sign_count != 0U) {
        rs_format_putc(output, sign);
    }
    if (prefix_count != 0U) {
        rs_format_putc(output, prefix[0]);
        if (prefix_count == 2U) {
            rs_format_putc(output, prefix[1]);
        }
    }
    if (!left_align && zero_pad && !has_precision) {
        rs_format_repeat(output, '0', padding);
    }
    rs_format_repeat(output, '0', zero_count);
    for (size_t index = 0U; index < digit_count; ++index) {
        rs_format_putc(output, digits[index]);
    }
    if (left_align) {
        rs_format_repeat(output, ' ', padding);
    }
}

static int rs_vformat(rs_format_output_t *output, const char *format, va_list *args) {
    if ((output == NULL) || (format == NULL) || (args == NULL)) {
        return -1;
    }

    while (*format != '\0') {
        bool left_align = false;
        bool force_sign = false;
        bool space_sign = false;
        bool zero_pad = false;
        bool alternate = false;
        bool has_precision = false;
        size_t width = 0U;
        size_t precision = 0U;
        rs_format_length_t length = RS_FMT_NONE;
        char conversion;

        if (*format != '%') {
            rs_format_putc(output, *format++);
            continue;
        }
        ++format;

        for (;;) {
            if (*format == '-') {
                left_align = true;
            } else if (*format == '+') {
                force_sign = true;
            } else if (*format == ' ') {
                space_sign = true;
            } else if (*format == '0') {
                zero_pad = true;
            } else if (*format == '#') {
                alternate = true;
            } else {
                break;
            }
            ++format;
        }
        while ((*format >= '0') && (*format <= '9')) {
            width = (width * 10U) + (size_t)(*format - '0');
            ++format;
        }
        if (*format == '.') {
            has_precision = true;
            ++format;
            while ((*format >= '0') && (*format <= '9')) {
                precision = (precision * 10U) + (size_t)(*format - '0');
                ++format;
            }
        }
        if (*format == 'h') {
            length = RS_FMT_H;
            ++format;
            if (*format == 'h') {
                length = RS_FMT_HH;
                ++format;
            }
        } else if (*format == 'l') {
            length = RS_FMT_L;
            ++format;
            if (*format == 'l') {
                length = RS_FMT_LL;
                ++format;
            }
        } else if (*format == 'z') {
            length = RS_FMT_Z;
            ++format;
        }

        conversion = *format;
        if (conversion == '\0') {
            break;
        }
        ++format;

        switch (conversion) {
        case 'd':
        case 'i': {
            const int64_t signed_value = rs_format_signed_arg(args, length);
            const bool negative = signed_value < 0;
            const uint64_t value =
                negative ? (uint64_t)(-(signed_value + 1)) + 1U : (uint64_t)signed_value;
            rs_format_number(output, value, negative, 10U, false, left_align, zero_pad, force_sign,
                             space_sign, width, precision, has_precision, false);
            break;
        }
        case 'u':
            rs_format_number(output, rs_format_unsigned_arg(args, length), false, 10U, false,
                             left_align, zero_pad, false, false, width, precision, has_precision,
                             false);
            break;
        case 'x':
        case 'X':
            rs_format_number(output, rs_format_unsigned_arg(args, length), false, 16U,
                             conversion == 'X', left_align, zero_pad, false, false, width,
                             precision, has_precision, alternate);
            break;
        case 'o':
            rs_format_number(output, rs_format_unsigned_arg(args, length), false, 8U, false,
                             left_align, zero_pad, false, false, width, precision, has_precision,
                             alternate);
            break;
        case 'p':
            rs_format_number(output, (uintptr_t)va_arg(*args, void *), false, 16U, false,
                             left_align, true, false, false, width, precision, has_precision, true);
            break;
        case 'c': {
            const char value = (char)va_arg(*args, int);
            if (!left_align) {
                rs_format_repeat(output, ' ', width > 1U ? width - 1U : 0U);
            }
            rs_format_putc(output, value);
            if (left_align) {
                rs_format_repeat(output, ' ', width > 1U ? width - 1U : 0U);
            }
            break;
        }
        case 's': {
            const char *value = va_arg(*args, const char *);
            size_t length_value;
            if (value == NULL) {
                value = "(null)";
            }
            length_value = strlen(value);
            if (has_precision && (length_value > precision)) {
                length_value = precision;
            }
            if (!left_align) {
                rs_format_repeat(output, ' ', width > length_value ? width - length_value : 0U);
            }
            for (size_t index = 0U; index < length_value; ++index) {
                rs_format_putc(output, value[index]);
            }
            if (left_align) {
                rs_format_repeat(output, ' ', width > length_value ? width - length_value : 0U);
            }
            break;
        }
        case '%':
            rs_format_putc(output, '%');
            break;
        default:
            rs_format_putc(output, '%');
            rs_format_putc(output, conversion);
            break;
        }
    }

    return (output->count > (size_t)INT32_MAX) ? -1 : (int)output->count;
}

static void rs_console_sink(void *context, char value) {
    (void)context;
    putch(value);
}

int rs_vsnprintf(char *dst, size_t dst_size, const char *format, va_list args) {
    rs_format_output_t output = {dst, dst_size, 0U, NULL, NULL};
    va_list copy;
    int result;

    va_copy(copy, args);
    result = rs_vformat(&output, format, &copy);
    va_end(copy);

    if ((dst != NULL) && (dst_size > 0U)) {
        const size_t terminator = output.count < (dst_size - 1U) ? output.count : dst_size - 1U;
        dst[terminator] = '\0';
    }
    return result;
}

int rs_snprintf(char *dst, size_t dst_size, const char *format, ...) {
    int result;
    va_list args;

    va_start(args, format);
    result = rs_vsnprintf(dst, dst_size, format, args);
    va_end(args);
    return result;
}

int rs_printf(const char *format, ...) {
    int result;
    va_list args;

    rs_format_output_t output = {NULL, 0U, 0U, rs_console_sink, NULL};
    va_start(args, format);
    result = rs_vformat(&output, format, &args);
    va_end(args);
    return result;
}

int vsnprintf(char *dst, size_t dst_size, const char *format, va_list args) {
    return rs_vsnprintf(dst, dst_size, format, args);
}

int snprintf(char *dst, size_t dst_size, const char *format, ...) {
    int result;
    va_list args;

    va_start(args, format);
    result = rs_vsnprintf(dst, dst_size, format, args);
    va_end(args);
    return result;
}

int printf(const char *format, ...) {
    int result;
    va_list args;
    rs_format_output_t output = {NULL, 0U, 0U, rs_console_sink, NULL};

    va_start(args, format);
    result = rs_vformat(&output, format, &args);
    va_end(args);
    return result;
}
