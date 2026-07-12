int __clzsi2(unsigned int value);

int __clzsi2(unsigned int value) {
    int count = 0;

    if (value == 0U) {
        return 32;
    }
    while ((value & 0x80000000U) == 0U) {
        ++count;
        value <<= 1U;
    }
    return count;
}
