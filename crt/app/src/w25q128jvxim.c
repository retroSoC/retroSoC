#include <stdbool.h>
#include <tinyprintf.h>
#include <tinystring.h>
#include <tinyqspi.h>
// #include <tinyspisd.h>
// #include <tinydma.h>

// static void norflash_enter_quad_mode() {
    // qspi0_spi_wr_cmd(0x06); // NOTE: set QE=1 in status reg for QSPI/QPI
    // qspi0_spi_wr_data(0x31, dumlen=0, datalen=1);
// }

// static void norflash_quit_quad_mode() {

// }


static void norflash_spi_id() {
    // manu/dev id
    uint32_t res_list[2];
    qspi0_spi_rd((uint32_t)1, (uint32_t)0x90000000,
                 (uint32_t)3, (uint32_t)0x00000000,
                 (uint32_t)0,
                 (uint32_t)1, (uint32_t)2, res_list);
    printf("manu/dev id: %x\n", res_list[0]);
    // uni id
    qspi0_spi_rd((uint32_t)1, (uint32_t)0x4B000000,
                 (uint32_t)0, (uint32_t)0x00000000,
                 (uint32_t)32,
                 (uint32_t)2, (uint32_t)4, res_list);
    printf("uni id: %x %x\n", res_list[0], res_list[1]);
    // jedec id
    qspi0_spi_rd((uint32_t)1, (uint32_t)0x9F000000,
                 (uint32_t)0, (uint32_t)0x00000000,
                 (uint32_t)0,
                 (uint32_t)1, (uint32_t)3, res_list);
    printf("mem/cap id: %x\n", res_list[0]);
}

// static void norflash_dspi_id() {
    // qspi0_dspi_rd_data(val_list, dumlen=0, datalen=2); // 1-2-2(92h+4B-adr, lowest byte need to set Fxh)
// }


// static void norflash_quad_id() {
// qspi0_qspi_rd_data(val_list, dumlen=4, datalen=2); // 1-4-4(94h+4B-adr+1/2B-dum, lowest byte need to set Fxh)

// }

static void norflash_spi_status() {
    // qpis0_qpi_rd_data(val_list, dumlen=0, datalen=1); // 4-4-4(05/35/15h)
}


// static void norflash_qpi_status() {
    // qpis0_qpi_rd_data(val_list, dumlen=0, datalen=1); // 4-4-4(05/35/15h)
// }

static void norflash_spi_test() {
    printf("norflash spi test\n");
    norflash_spi_id();
    norflash_spi_status();
    // qspi0_spi_wr_cmd(0x06);
    // qspi0_spi_wr_data(val_list, len); // (02h+3B-adr)
    // rd
    // qspi0_spi_rd(val_list, dumlen=0, datalen); // 1-1-1(03h+3B-adr)
    // qspi0_spi_rd(val_list, dumlen=8, datalen); // 1-1-1(0Bh+3B-adr+1B-dum)
}

// static void norflash_dspi_test() {
    // qspi0_dspi_init();
    // qspi0_spi_wr_cmd(0x06);
    // qspi0_dspi_wr_data(val_list, len);
    // rd
    // qspi0_dspi_rd_data(val_list, dumlen=8, datalen); // 1-1-2(3Bh+3B-adr+1B-dum)
    // qspi0_dspi_rd_data(val_list, dumlen=0, datalen); // 1-2-2(BBh+4B-adr, lowest addr need to set Fxh)
// }

// static void norflash_qspi_test() {
    // norflash_enter_quad_mode();
    // qspi0_qspi_init();
    // qspi0_spi_wr_cmd(0x06);
    // qspi0_qspi_wr_data(val_list, len); // 1-1-4(32h+3B-adr)
    // rd: 
    // qspi0_qspi_rd_data(val_list, dumlen=8, datalen); // 1-1-4(6Bh+3B-adr+1B-dum)
    // qspi0_qspi_rd_data(val_list, dumlen=4, datalen); // 1-4-4(EBh+4B-adr+1/2B-dum, lowest byte need to set Fxh)
// }

// static void norflash_qpi_test() {
    // enter: 38h, exit FFh
    // qspi0_spi_wr_cmd(0x38); // enter QPI mode
    // qspi0_qpi_wr_data(val_list, len); // 4-4-4(02h+3B-adr)
    // rd
    // qspi0_qpi_rd_data(val_list, dumlen=8, datalen); // 4-4-4(0Bh+3B-adr+1B-dum)
    // qspi0_qpi_rd_data(val_list, dumlen=2, datalen); // 4-4-4(EBh+4B-adr+1/4B-dum, lowest byte need to set Fxh)
    // qspi0_spi_wr_cmd(0xFF); // exit QPI mode
// }

void ip_norflash_test() {
    printf("[NATV IP] qspi nor flash test\n");

    QSPI0_InitStruct_t qspi0 = {
        (uint32_t)0, 
        (uint32_t)0b0001,
        (uint32_t)0,
        (uint32_t)250,
        (uint32_t)140,
        (uint32_t)24,
        (uint32_t)10
    };

    qspi0_init(qspi0);

    norflash_spi_test();
    // norflash_dspi_test();
    // norflash_qspi_test();
    // norflash_qpi_test();
}