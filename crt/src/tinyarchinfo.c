#include <firmware.h>
#include <tinyprintf.h>
#include <tinyarchinfo.h>

void ip_archinfo_test()
{
    printf("[CUST IP] archinfo test\n");
    printf("[ARCHINFO SYS] %x\n", reg_cust_archinfo_sys);
    printf("[ARCHINFO IDL] %x\n", reg_cust_archinfo_idl);
    printf("[ARCHINFO IDH] %x\n", reg_cust_archinfo_idh);
}