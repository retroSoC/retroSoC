#include <stdbool.h>
#include <tinyprintf.h>
#include <tinystring.h>
#include <tinyqspi.h>
// #include <tinyspisd.h>
// #include <tinydma.h>

static void norflash_spi_wr_en() {
    uint32_t data[] = {0};

    qspi0_wr((uint32_t)1, (uint32_t)1, (uint32_t)0x06000000,
             (uint32_t)0, (uint32_t)3, (uint32_t)0x00000000,
             (uint32_t)0,
             (uint32_t)0, (uint32_t)1, (uint32_t)2,
             data);
}

static void norflash_spi_wr_data(uint32_t* data, uint32_t len) {
    printf("len: %d\n", len);
    qspi0_wr((uint32_t)1, (uint32_t)1, (uint32_t)0x02000000,
             (uint32_t)1, (uint32_t)3, (uint32_t)0x00000000,
             (uint32_t)0,
             (uint32_t)1, len, (uint32_t)4,
             data);
}


static void norflash_spi_rd_data(uint32_t len) {
    uint32_t data[64] = {0};

    qspi0_rd((uint32_t)1, (uint32_t)1, (uint32_t)0x03000000,
             (uint32_t)1, (uint32_t)3, (uint32_t)0x00000000,
             (uint32_t)0,
             (uint32_t)1, len, (uint32_t)4,
             data);

    printf("rd: ");
    for(uint32_t i = 0; i < len; ++i) printf(" %x", data[i]);
    printf("\n");

    qspi0_rd((uint32_t)1, (uint32_t)1, (uint32_t)0x0B000000,
             (uint32_t)1, (uint32_t)3, (uint32_t)0x00000000,
             (uint32_t)8,
             (uint32_t)1, len, (uint32_t)4,
             data);

    printf("rd: ");
    for(uint32_t i = 0; i < len; ++i) printf(" %x", data[i]);
    printf("\n");
}

static void norflash_dspi_rd_data(uint32_t len) {
    printf("len: %d", len);
    uint32_t data[64] = {0};

    qspi0_rd((uint32_t)1, (uint32_t)1, (uint32_t)0x3B000000,
             (uint32_t)1, (uint32_t)3, (uint32_t)0x00000000,
             (uint32_t)8,
             (uint32_t)2, len, (uint32_t)4,
             data);

    printf("rd: ");
    for(uint32_t i = 0; i < len; ++i) printf(" %x", data[i]);
    printf("\n");

    qspi0_rd((uint32_t)1, (uint32_t)1, (uint32_t)0xBB000000,
             (uint32_t)2, (uint32_t)4, (uint32_t)0x000000F0,
             (uint32_t)0,
             (uint32_t)2, len, (uint32_t)4,
             data);

    printf("rd: ");
    for(uint32_t i = 0; i < len; ++i) printf(" %x", data[i]);
    printf("\n");
}

static void norflash_spi_id() {
    // manu/dev id
    uint32_t data[2];
    qspi0_rd((uint32_t)1, (uint32_t)1, (uint32_t)0x90000000,
             (uint32_t)1, (uint32_t)3, (uint32_t)0x00000000,
             (uint32_t)0,
             (uint32_t)1, (uint32_t)1, (uint32_t)2,
             data);
    printf("manu/dev id: %x\n", data[0]);
    // uni id
    qspi0_rd((uint32_t)1, (uint32_t)1, (uint32_t)0x4B000000,
             (uint32_t)0, (uint32_t)0, (uint32_t)0x00000000,
             (uint32_t)32,
             (uint32_t)1, (uint32_t)2, (uint32_t)4,
             data);
    printf("uni id: %x %x\n", data[0], data[1]);
    // jedec id
    qspi0_rd((uint32_t)1, (uint32_t)1, (uint32_t)0x9F000000,
             (uint32_t)0, (uint32_t)0, (uint32_t)0x00000000,
             (uint32_t)0,
             (uint32_t)1, (uint32_t)1, (uint32_t)3,
             data);
    printf("mem/cap id: %x\n", data[0]);
}

static void norflash_dspi_id() {
     // manu/dev id
    uint32_t data[2];
    qspi0_rd((uint32_t)1, (uint32_t)1, (uint32_t)0x92000000,
             (uint32_t)2, (uint32_t)4, (uint32_t)0x000000F0,
             (uint32_t)0,
             (uint32_t)2, (uint32_t)1, (uint32_t)2,
             data);
    printf("manu/dev id: %x\n", data[0]);
}


static void norflash_qspi_id() {
    // manu/dev id
    uint32_t data[2];
    qspi0_rd((uint32_t)1, (uint32_t)1, (uint32_t)0x94000000,
             (uint32_t)3, (uint32_t)4, (uint32_t)0x000000F0,
             (uint32_t)4,
             (uint32_t)3, (uint32_t)1, (uint32_t)2,
             data);
    printf("manu/dev id: %x\n", data[0]);
}

static void norflash_spi_status() {
    uint32_t data[2];
    uint32_t cmd[] = {(uint32_t)0x05000000, (uint32_t)0x35000000, (uint32_t)0x15000000,};

    for(int i = 0; i < 3; ++i) {
        qspi0_rd((uint32_t)1, (uint32_t)1, cmd[i],
                 (uint32_t)0, (uint32_t)0, (uint32_t)0x00000000,
                 (uint32_t)0,
                 (uint32_t)1, (uint32_t)1, (uint32_t)1, data);
        printf("status reg %d: %x\n", i, data[0]);
    }
}


// static void norflash_qpi_status() {
    // qpis0_qpi_rd_data(val_list, dumlen=0, datalen=1); // 4-4-4(05/35/15h)
// }

static void norflash_enter_quad_mode() {
    uint32_t data[] = {0};


    qspi0_rd((uint32_t)1, (uint32_t)1, (uint32_t)0x35000000,
             (uint32_t)0, (uint32_t)0, (uint32_t)0x00000000,
             (uint32_t)0,
             (uint32_t)1, (uint32_t)1, (uint32_t)1, data);

    // set QE=1 in status reg 2 for QSPI/QPI
    data[0] = data[0] | 0x02;

    norflash_spi_wr_en();
    qspi0_wr((uint32_t)1, (uint32_t)1, (uint32_t)0x31000000,
             (uint32_t)0, (uint32_t)3, (uint32_t)0x00000000,
             (uint32_t)0,
             (uint32_t)1, (uint32_t)1, (uint32_t)2,
             data);

    norflash_spi_status();
}

// static void norflash_quit_quad_mode() {

// }

static void norflash_spi_test() {
    printf("norflash spi test\n");
    uint32_t wr_data[] = {0x23456788, 0x00FFEE30, 0x418461AB, 0xC252DE21, 0x00550022, 0x00002266};

    norflash_spi_id();
    norflash_spi_status();

    norflash_spi_wr_en();
    norflash_spi_wr_data(wr_data, sizeof(wr_data)/sizeof(wr_data[0]));
    norflash_spi_rd_data(sizeof(wr_data)/sizeof(wr_data[0]));
}

static void norflash_dspi_test() {
    printf("norflash dspi test\n");
    uint32_t wr_data[] = {0x23456788, 0x00FFEE30, 0x418461AB, 0xC252DE21, 0x00550022, 0x00002266};

    norflash_dspi_id();
    norflash_spi_wr_en();
    norflash_spi_wr_data(wr_data, sizeof(wr_data)/sizeof(wr_data[0]));
    // rd
    norflash_dspi_rd_data(sizeof(wr_data)/sizeof(wr_data[0]));
}

static void norflash_qspi_test() {
    printf("norflash qspi test\n");
    norflash_enter_quad_mode();
    norflash_qspi_id();

    // qspi0_spi_wr_cmd(0x06);
    // qspi0_qspi_wr_data(val_list, len); // 1-1-4(32h+3B-adr)
    // rd: 
    // qspi0_qspi_rd_data(val_list, dumlen=8, datalen); // 1-1-4(6Bh+3B-adr+1B-dum)
    // qspi0_qspi_rd_data(val_list, dumlen=4, datalen); // 1-4-4(EBh+4B-adr+1/2B-dum, lowest byte need to set Fxh)
}

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

    // norflash_spi_test();
    norflash_dspi_test();
    norflash_qspi_test();
    // norflash_qpi_test();
}