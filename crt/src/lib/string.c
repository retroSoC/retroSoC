#include <retrosoc/lib/string.h>

size_t strlen(const char *str) {
    const char *cursor = str;

    if (str == NULL) {
        return 0U;
    }

    while (*cursor != '\0') {
        ++cursor;
    }
    return (size_t)(cursor - str);
}

char *strcpy(char *dst, const char *src) {
    char *cursor = dst;

    if ((dst == NULL) || (src == NULL)) {
        return dst;
    }

    do {
        *cursor = *src;
        ++cursor;
        ++src;
    } while (*(cursor - 1) != '\0');
    return dst;
}

char *strncpy(char *dst, const char *src, size_t count) {
    size_t index;

    if ((dst == NULL) || (src == NULL)) {
        return dst;
    }

    for (index = 0U; index < count; ++index) {
        dst[index] = src[index];
        if (src[index] == '\0') {
            ++index;
            break;
        }
    }
    while (index < count) {
        dst[index] = '\0';
        ++index;
    }
    return dst;
}

char *strcat(char *dst, const char *src) {
    if ((dst == NULL) || (src == NULL)) {
        return dst;
    }
    return strcpy(dst + strlen(dst), src);
}

int strcmp(const char *lhs, const char *rhs) {
    unsigned char left;
    unsigned char right;

    if (lhs == rhs) {
        return 0;
    }
    if (lhs == NULL) {
        return -1;
    }
    if (rhs == NULL) {
        return 1;
    }

    do {
        left = (unsigned char)*lhs++;
        right = (unsigned char)*rhs++;
    } while ((left != '\0') && (left == right));
    return (int)left - (int)right;
}

int strncmp(const char *lhs, const char *rhs, size_t count) {
    size_t index;

    if ((count == 0U) || (lhs == rhs)) {
        return 0;
    }
    if (lhs == NULL) {
        return -1;
    }
    if (rhs == NULL) {
        return 1;
    }

    for (index = 0U; index < count; ++index) {
        const unsigned char left = (unsigned char)lhs[index];
        const unsigned char right = (unsigned char)rhs[index];
        if (left != right) {
            return (int)left - (int)right;
        }
        if (left == '\0') {
            return 0;
        }
    }
    return 0;
}

void *memset(void *dst, int value, size_t count) {
    unsigned char *cursor = (unsigned char *)dst;
    size_t index;

    if (dst == NULL) {
        return NULL;
    }
    for (index = 0U; index < count; ++index) {
        cursor[index] = (unsigned char)value;
    }
    return dst;
}

void *memmove(void *dst, const void *src, size_t count) {
    unsigned char *output = (unsigned char *)dst;
    const unsigned char *input = (const unsigned char *)src;

    if ((dst == NULL) || (src == NULL) || (dst == src) || (count == 0U)) {
        return dst;
    }

    if ((output > input) && (output < (input + count))) {
        while (count-- != 0U) {
            output[count] = input[count];
        }
    } else {
        size_t index;
        for (index = 0U; index < count; ++index) {
            output[index] = input[index];
        }
    }
    return dst;
}

void *memcpy(void *dst, const void *src, size_t count) {
    return memmove(dst, src, count);
}

int memcmp(const void *lhs, const void *rhs, size_t count) {
    const unsigned char *left = (const unsigned char *)lhs;
    const unsigned char *right = (const unsigned char *)rhs;
    size_t index;

    if ((count == 0U) || (lhs == rhs)) {
        return 0;
    }
    if (lhs == NULL) {
        return -1;
    }
    if (rhs == NULL) {
        return 1;
    }

    for (index = 0U; index < count; ++index) {
        if (left[index] != right[index]) {
            return (int)left[index] - (int)right[index];
        }
    }
    return 0;
}

char *strchr(const char *str, int value) {
    const char target = (char)value;

    if (str == NULL) {
        return NULL;
    }
    do {
        if (*str == target) {
            return (char *)str;
        }
    } while (*str++ != '\0');
    return NULL;
}

size_t rs_strlcpy(char *dst, const char *src, size_t dst_size) {
    const size_t src_size = strlen(src);
    size_t copied = 0U;

    if ((dst == NULL) || (src == NULL) || (dst_size == 0U)) {
        return src_size;
    }

    while ((copied + 1U < dst_size) && (src[copied] != '\0')) {
        dst[copied] = src[copied];
        ++copied;
    }
    dst[copied] = '\0';
    return src_size;
}

size_t rs_strlcat(char *dst, const char *src, size_t dst_size) {
    const size_t dst_length = strlen(dst);
    const size_t src_length = strlen(src);

    if ((dst == NULL) || (src == NULL) || (dst_size == 0U)) {
        return dst_length + src_length;
    }
    if (dst_length >= dst_size) {
        return dst_size + src_length;
    }

    (void)rs_strlcpy(dst + dst_length, src, dst_size - dst_length);
    return dst_length + src_length;
}

void rs_trim_whitespace(char *str) {
    char *start;
    char *end;

    if (str == NULL) {
        return;
    }

    start = str;
    while ((*start == ' ') || (*start == '\t')) {
        ++start;
    }
    if (*start == '\0') {
        *str = '\0';
        return;
    }

    end = start + strlen(start);
    while ((end > start) &&
           ((end[-1] == ' ') || (end[-1] == '\t') || (end[-1] == '\r') || (end[-1] == '\n'))) {
        --end;
    }
    *end = '\0';
    if (start != str) {
        (void)memmove(str, start, (size_t)(end - start) + 1U);
    }
}

void rs_remove_suffix(char *dst, size_t dst_size, const char *src, char separator) {
    const char *cursor;
    size_t length;

    if ((dst == NULL) || (dst_size == 0U) || (src == NULL)) {
        return;
    }

    length = strlen(src);
    cursor = src + length;
    while ((cursor > src) && (cursor[-1] != separator)) {
        --cursor;
    }
    if (cursor == src) {
        (void)rs_strlcpy(dst, src, dst_size);
        return;
    }

    length = (size_t)(cursor - src - 1);
    if (length >= dst_size) {
        length = dst_size - 1U;
    }
    (void)memcpy(dst, src, length);
    dst[length] = '\0';
}
