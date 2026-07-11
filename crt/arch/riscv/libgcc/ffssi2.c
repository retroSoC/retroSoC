int __ffssi2(unsigned int value);

int __ffssi2(unsigned int value) {
    int position = 1;

    if (value == 0U) {
        return 0;
    }
    while ((value & 1U) == 0U) {
        ++position;
        value >>= 1U;
    }
    return position;
}
