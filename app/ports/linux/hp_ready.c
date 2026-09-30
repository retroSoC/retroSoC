/* Linux-only acceptance helper; the freestanding SDK does not depend on libc. */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv) {
    uint32_t error = 0U;
    int descriptor;
    void *mapping;
    volatile uint32_t *mailbox;
    if (argc == 2) {
        if ((argv[1][0] == '1') && (argv[1][1] >= '1') && (argv[1][1] <= '7') &&
            (argv[1][2] == '\0')) {
            error = 10U + (uint32_t)(argv[1][1] - '0');
        } else {
            error = 20U;
        }
    } else if (argc != 1) {
        error = 21U;
    }
    descriptor = open("/dev/mem", O_RDWR | O_SYNC);
    if (descriptor < 0) {
        (void)puts("HP_LINUX_INIT_FAILED devmem");
        return 1;
    }
    mapping = mmap(NULL, 4096U, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0x10019000);
    if (mapping == MAP_FAILED) {
        (void)puts("HP_LINUX_INIT_FAILED mmap");
        (void)close(descriptor);
        return 1;
    }
    mailbox = (volatile uint32_t *)mapping;
    if (error == 0U) {
        (void)puts("retroSoC HP Linux ready");
    } else {
        (void)printf("HP_LINUX_INIT_FAILED code=%u\n", error);
    }
    (void)fflush(stdout);
    mailbox[8] = (error == 0U) ? 1U : 3U;
    mailbox[9] = (error == 0U) ? UINT32_C(0x4C4E5801) : error;
    mailbox[10] = 1U;
    __asm__ volatile("fence iorw, iorw" ::: "memory");
    mailbox[11] = 1U;
    for (;;) {
        (void)pause();
    }
}
