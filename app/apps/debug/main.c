void rs_debug_breakpoint_target(void);

__attribute__((noinline, used)) void rs_debug_breakpoint_target(void) {
    __asm__ volatile("nop" ::: "memory");
}

int main(void) {
    for (;;) {
        rs_debug_breakpoint_target();
    }
}
