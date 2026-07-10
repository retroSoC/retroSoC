#include <firmware.h>
#include <rs_printf.h>
#include <rs_archinfo.h>

void ip_archinfo_test(int argc, char **argv) {
    (void) argc;
    (void) argv;
    printf("[APB IP] archinfo test\n");
    printf("[ARCHINFO SYS] %x\n", reg_archinfo_sys);
    printf("[ARCHINFO IDL] %x\n", reg_archinfo_idl);
    printf("[ARCHINFO IDH] %x\n", reg_archinfo_idh);
}
