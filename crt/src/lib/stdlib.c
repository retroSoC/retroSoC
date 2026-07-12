#include <limits.h>
#include <stdbool.h>
#include <stddef.h>

#include <retrosoc/lib/stdlib.h>

static uint32_t rs_rand_state = 1U;

rs_status_t rs_strtoi32(const char *str, int32_t *value) {
    uint32_t magnitude = 0U;
    bool negative = false;

    if ((str == NULL) || (value == NULL)) {
        return RS_EINVAL;
    }

    while ((*str == ' ') || (*str == '\t')) {
        ++str;
    }
    if ((*str == '+') || (*str == '-')) {
        negative = (*str == '-');
        ++str;
    }
    if ((*str < '0') || (*str > '9')) {
        return RS_EFORMAT;
    }

    while ((*str >= '0') && (*str <= '9')) {
        const uint32_t digit = (uint32_t)(*str - '0');
        const uint32_t limit = negative ? ((uint32_t)INT32_MAX + 1U) : (uint32_t)INT32_MAX;
        if ((magnitude > (limit / 10U)) ||
            ((magnitude == (limit / 10U)) && (digit > (limit % 10U)))) {
            return RS_EFORMAT;
        }
        magnitude = (magnitude * 10U) + digit;
        ++str;
    }

    if (*str != '\0') {
        return RS_EFORMAT;
    }
    if (negative) {
        *value = (magnitude == ((uint32_t)INT32_MAX + 1U)) ? INT32_MIN : -(int32_t)magnitude;
    } else {
        *value = (int32_t)magnitude;
    }
    return RS_OK;
}

rs_status_t rs_utoa(uint32_t value, char *dst, uint32_t base) {
    static const char digits[] = "0123456789ABCDEF";
    char reversed[33];
    uint32_t count = 0U;
    uint32_t index;

    if ((dst == NULL) || (base < 2U) || (base > 16U)) {
        return RS_EINVAL;
    }

    do {
        reversed[count] = digits[value % base];
        ++count;
        value /= base;
    } while (value != 0U);

    for (index = 0U; index < count; ++index) {
        dst[index] = reversed[count - index - 1U];
    }
    dst[count] = '\0';
    return RS_OK;
}

int atoi(const char *str) {
    int32_t value = 0;
    return (rs_strtoi32(str, &value) == RS_OK) ? (int)value : 0;
}

char *itoa(unsigned int value, char *dst, int base) {
    if (rs_utoa((uint32_t)value, dst, (uint32_t)base) != RS_OK) {
        return NULL;
    }
    return dst;
}

int abs(int value) {
    return (value == INT_MIN) ? INT_MAX : ((value < 0) ? -value : value);
}

int rand(void) {
    rs_rand_state = (rs_rand_state * 1103515245U) + 12345U;
    return (int)((rs_rand_state >> 16U) & (uint32_t)RAND_MAX);
}

void srand(unsigned int seed) {
    rs_rand_state = seed;
}
