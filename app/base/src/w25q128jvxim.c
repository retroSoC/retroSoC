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

static void norflash_qpi_wr_en() {
    uint32_t data[] = {0};

    qspi0_wr((uint32_t)3, (uint32_t)1, (uint32_t)0x06000000,
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

static void norflash_qspi_wr_data(uint32_t* data, uint32_t len) {
    printf("len: %d\n", len);
    qspi0_wr((uint32_t)1, (uint32_t)1, (uint32_t)0x32000000,
             (uint32_t)1, (uint32_t)3, (uint32_t)0x00000000,
             (uint32_t)0,
             (uint32_t)3, len, (uint32_t)4,
             data);
}

static void norflash_qpi_wr_data(uint32_t* data, uint32_t len) {
    printf("len: %d\n", len);
    qspi0_wr((uint32_t)3, (uint32_t)1, (uint32_t)0x02000000,
             (uint32_t)3, (uint32_t)3, (uint32_t)0x00000000,
             (uint32_t)0,
             (uint32_t)3, len, (uint32_t)4,
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

static void norflash_qspi_rd_data(uint32_t len) {
    printf("len: %d", len);
    uint32_t data[64] = {0};

    qspi0_rd((uint32_t)1, (uint32_t)1, (uint32_t)0x6B000000,
             (uint32_t)1, (uint32_t)3, (uint32_t)0x00000000,
             (uint32_t)8,
             (uint32_t)3, len, (uint32_t)4,
             data);

    printf("rd: ");
    for(uint32_t i = 0; i < len; ++i) printf(" %x", data[i]);
    printf("\n");

    qspi0_rd((uint32_t)1, (uint32_t)1, (uint32_t)0xEB000000,
             (uint32_t)3, (uint32_t)4, (uint32_t)0x000000F0,
             (uint32_t)4,
             (uint32_t)3, len, (uint32_t)4,
             data);

    printf("rd: ");
    for(uint32_t i = 0; i < len; ++i) printf(" %x", data[i]);
    printf("\n");
}

static void norflash_qpi_rd_data(uint32_t len) {
    printf("len: %d", len);
    uint32_t data[64] = {0};

    qspi0_rd((uint32_t)3, (uint32_t)1, (uint32_t)0x0B000000,
             (uint32_t)3, (uint32_t)3, (uint32_t)0x00000000,
             (uint32_t)2,
             (uint32_t)3, len, (uint32_t)4,
             data);

    printf("rd: ");
    for(uint32_t i = 0; i < len; ++i) printf(" %x", data[i]);
    printf("\n");

    qspi0_rd((uint32_t)3, (uint32_t)1, (uint32_t)0xEB000000,
             (uint32_t)3, (uint32_t)4, (uint32_t)0x000000F0,
             (uint32_t)4,
             (uint32_t)3, len, (uint32_t)4,
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
    uint32_t data[2];
    // manu/dev id
    qspi0_rd((uint32_t)1, (uint32_t)1, (uint32_t)0x94000000,
             (uint32_t)3, (uint32_t)4, (uint32_t)0x000000F0,
             (uint32_t)4,
             (uint32_t)3, (uint32_t)1, (uint32_t)2,
             data);
    printf("manu/dev id: %x\n", data[0]);
}

static void norflash_qpi_id() {
    uint32_t data[2];
    // jedec id
    qspi0_rd((uint32_t)3, (uint32_t)1, (uint32_t)0x9F000000,
             (uint32_t)0, (uint32_t)0, (uint32_t)0x00000000,
             (uint32_t)0,
             (uint32_t)3, (uint32_t)1, (uint32_t)3,
             data);
    printf("mem/cap id: %x\n", data[0]);
}

static void norflash_spi_status() {
    uint32_t data[2];
    uint32_t cmd[] = {(uint32_t)0x05000000, (uint32_t)0x35000000, (uint32_t)0x15000000,};

    for(int i = 0; i < 3; ++i) {
        qspi0_rd((uint32_t)1, (uint32_t)1, cmd[i],
                 (uint32_t)0, (uint32_t)0, (uint32_t)0x00000000,
                 (uint32_t)0,
                 (uint32_t)1, (uint32_t)1, (uint32_t)1,
                 data);
        printf("status reg %d: %x\n", i, data[0]);
    }
}


static void norflash_qpi_status() {
    uint32_t data[2];
    uint32_t cmd[] = {(uint32_t)0x05000000, (uint32_t)0x35000000, (uint32_t)0x15000000,};

    for(int i = 0; i < 3; ++i) {
        qspi0_rd((uint32_t)3, (uint32_t)1, cmd[i],
                 (uint32_t)0, (uint32_t)0, (uint32_t)0x00000000,
                 (uint32_t)0,
                 (uint32_t)3, (uint32_t)1, (uint32_t)1,
                 data);
        printf("status reg %d: %x\n", i, data[0]);
    }

    // qpis0_qpi_rd_data(val_list, dumlen=0, datalen=1); // 4-4-4(05/35/15h)
}

static void norflash_enter_quad_mode() {
    uint32_t data[] = {0};

    qspi0_rd((uint32_t)1, (uint32_t)1, (uint32_t)0x35000000,
             (uint32_t)0, (uint32_t)0, (uint32_t)0x00000000,
             (uint32_t)0,
             (uint32_t)1, (uint32_t)1, (uint32_t)1,
             data);

    // set QE=1 in status reg 2 for QSPI/QPI
    data[0] = (data[0] | 0x02) << 24;
    printf("data[0]: %x\n", data[0]);

    norflash_spi_wr_en();
    qspi0_wr((uint32_t)1, (uint32_t)1, (uint32_t)0x31000000,
             (uint32_t)0, (uint32_t)0, (uint32_t)0x00000000,
             (uint32_t)0,
             (uint32_t)1, (uint32_t)1, (uint32_t)1,
             data);

    norflash_spi_status();
}

static void norflash_enter_qpi_mode() {
    uint32_t data[] = {0};

    norflash_spi_wr_en();
    qspi0_wr((uint32_t)1, (uint32_t)1, (uint32_t)0x38000000,
             (uint32_t)0, (uint32_t)0, (uint32_t)0x00000000,
             (uint32_t)0,
             (uint32_t)0, (uint32_t)1, (uint32_t)1,
             data);
}

// need to assure in qpi mode before
static void norflash_quit_qpi_mode() {
    uint32_t data[] = {0};

    norflash_qpi_wr_en();
    qspi0_wr((uint32_t)3, (uint32_t)1, (uint32_t)0xFF000000,
             (uint32_t)0, (uint32_t)0, (uint32_t)0x00000000,
             (uint32_t)0,
             (uint32_t)0, (uint32_t)1, (uint32_t)1,
             data);
}

static void norflash_spi_test() {
    printf("\nnorflash spi test\n");
    uint32_t wr_data[] = {0x23456788, 0x00FFEE30, 0x418461AB, 0xC252DE21, 0x00550022, 0x00002266};

    norflash_spi_id();
    norflash_spi_status();

    norflash_spi_wr_en();
    norflash_spi_wr_data(wr_data, sizeof(wr_data)/sizeof(wr_data[0]));
    norflash_spi_rd_data(sizeof(wr_data)/sizeof(wr_data[0]));
}

static void norflash_dspi_test() {
    printf("\nnorflash dspi test\n");
    uint32_t wr_data[] = {0x23456788, 0x00FFEE30, 0x418461AB, 0xC252DE21, 0x00550022, 0x00002266};

    norflash_dspi_id();
    norflash_spi_wr_en();
    norflash_spi_wr_data(wr_data, sizeof(wr_data)/sizeof(wr_data[0]));
    // rd
    norflash_dspi_rd_data(sizeof(wr_data)/sizeof(wr_data[0]));
}

static void norflash_qspi_test() {
    printf("\nnorflash qspi test\n");
    uint32_t wr_data[] = {0x23456788, 0x00FFEE30, 0x418461AB, 0xC252DE21, 0x00550022, 0x00002266};

    norflash_enter_quad_mode();
    norflash_qspi_id();

    norflash_spi_wr_en();
    norflash_qspi_wr_data(wr_data, sizeof(wr_data)/sizeof(wr_data[0]));
    // rd:
    norflash_qspi_rd_data(sizeof(wr_data)/sizeof(wr_data[0]));
}

static void norflash_qpi_test() {
    printf("\nnorflash qpi test\n");
    uint32_t wr_data[] = {0x23456788, 0x00FFEE30, 0x418461AB, 0xC252DE21, 0x00550022, 0x00002266};

    norflash_enter_quad_mode();
    norflash_enter_qpi_mode();
    norflash_qpi_id();
    norflash_qpi_status();

    norflash_qpi_wr_en();
    norflash_qpi_wr_data(wr_data, sizeof(wr_data)/sizeof(wr_data[0]));
    // rd
    norflash_qpi_rd_data(sizeof(wr_data)/sizeof(wr_data[0]));
    norflash_quit_qpi_mode();
}

void ip_norflash_test(int argc, char **argv) {
    (void) argc;
    (void) argv;

    printf("[NATV IP] qspi nor flash test\n");

    QSPI0_InitStruct_t qspi0 = {
        (uint32_t)0, 
        (uint32_t)0b0001,
        (uint32_t)0,
        (uint32_t)250,
        (uint32_t)140,
        (uint32_t)24,
        (uint32_t)10,
        (uint32_t)0,
    };

    qspi0_init(qspi0);

    norflash_spi_test();
    norflash_dspi_test();
    norflash_qspi_test();
    norflash_qpi_test();
}