#include <firmware.h>
#include <tinyprint.h>
#include <tinyprintf.h>
#include <tinystring.h>
#include <tinysh.h>
#include <ff.h> // app/fat32

static char sh_argv_buf[MAX_CMD_ARGC][MAX_CMD_LEN];
static char *sh_argv[MAX_CMD_ARGC];
static uint8_t sh_argc;
static tinysh_cmd_t sh_cmd_list[MAX_CMD_NUM];
static uint8_t sh_cmd_len;
static char sh_history_table[MAX_CMD_HIST][MAX_CMD_LEN];
static uint8_t sh_history_idx;


uint8_t tinysh_register(char *name, char *info, void *handler) {
    if(!name || !handler || !strlen(name)) return 1;
    if(sh_cmd_len == MAX_CMD_NUM) return 1;

    for(uint8_t i = 0; i < sh_cmd_len; ++i) {
        if(strcmp(name, sh_cmd_list[i].name) == 0) return 1;
    }

    tinysh_cmd_t tmp = {name, info, handler};
    sh_cmd_list[sh_cmd_len++] = tmp;
    return 0;
}

// static void tinysh_search_cmd(char *cmd, uint8_t len) {

// }

static uint8_t tinysh_split_cmd(char *cmd) {
    sh_argc = 0;
    trim_whitespace(cmd);
    // printf("split original cmd: ==%s==\n", cmd);
    if (strlen(cmd) == 0) return 1;

    char sub_cmd[MAX_CMD_LEN];
    uint8_t tmp_len = 0;

    for(uint8_t i = 0; i < MAX_CMD_LEN; ++i) {
        if(cmd[i] == ' ') {
            sub_cmd[tmp_len] = 0;
            // printf("sub cmd: %s\n", sub_cmd);
            strcpy(sh_argv[sh_argc], sub_cmd);
            ++sh_argc;
            tmp_len = 0;
        } else {
            sub_cmd[tmp_len++] = cmd[i];
        }
    }

    strcpy(sh_argv[sh_argc], NULL);

    // printf("argc: %d\nargv:", sh_argc);
    for(uint8_t i = 0; i <= sh_argc; ++i) {
        printf(" %s", sh_argv[i] == NULL ? "NULL" : sh_argv[i]);
    }
    printf("\n");
    
    return 0;
}

static void tinysh_parse_and_exec(char *cmd) {
    uint8_t split_res = tinysh_split_cmd(cmd);
    if(split_res == (uint8_t)1) {
        printf("error input\n");
        return;
    }

    bool is_find = false;
    for(uint8_t i = 0; i < sh_cmd_len; ++i) {
        if(strcmp(sh_argv[0], sh_cmd_list[i].name) == 0) {
            is_find = true;
            sh_cmd_list[i].handler(sh_argc, sh_argv);
            break;
        }
    }

    if(!is_find) printf("cmd: %s not found\n", sh_argv[0]);
}

static void tinysh_help() {
    for(uint8_t i = 0; i < sh_cmd_len; ++i) {
        printf("cmd: %8s info: %20s\n", sh_cmd_list[i].name, sh_cmd_list[i].info);
    }
}

static void tinysh_history_list() {
    for(uint8_t i = 0; i < sh_history_idx; ++i) {
        printf("%3d %s\n", i, sh_history_table[i]);
    }
}

static void tinysh_welcome() {
    printf("================================\n");
    printf("           Tiny Shell           \n");
    printf("================================\n");
}

void tinysh_init() {
    sh_cmd_len = 0;
    sh_history_idx = 0;
    for(uint8_t i = 0; i < MAX_CMD_ARGC; ++i) {
        sh_argv[i] = sh_argv_buf[i];
    }
}

uint8_t tinysh_mount_fs(FATFS *fs) {
    FRESULT ff_res;
    ff_res = f_mount(fs, "0:", 1);
    switch(ff_res) {
        case FR_NO_FILESYSTEM:
            printf("[fatfs] no filesystem\n");
            return 1;
        break;
        case FR_OK:
           printf("[fatfs] mount done\n");
            return 0;
        break;
        default:
            printf("[fatfs] filesystem mount fail\n");
            return 1;
    }
}

void tinysh_unmount_fs() {
    f_mount(NULL, "0:", 1);
}

void tinysh_ls_cmd_fs() {

}

void tinysh_pwd_cmd_fs() {
    // FRESULT ff_res;
    // UINT buf_len = (UINT)100;
    // TCHAR path_name[buf_len];

    // ff_res = f_getcwd(path_name, buf_len);
    // if(ff_res == FR_OK) printf("%s\n", path_name);
}

void tinysh_fat32_file_cmd(int argc, char **argv) {

    if(argc != 2) {
        printf("file cmd param error\n");
        return;
    }

    printf("file name: %s\n", argv[1]);

    FILINFO ff_info;
    FRESULT ff_res;
    ff_res = f_stat(argv[1], &ff_info);

    switch(ff_res) {
        case FR_OK:
            printf("[attr]: %c%c%c%c%c ",
                   (ff_info.fattrib & AM_DIR) ? 'D' : '-',
                   (ff_info.fattrib & AM_RDO) ? 'R' : '-',
                   (ff_info.fattrib & AM_HID) ? 'H' : '-',
                   (ff_info.fattrib & AM_SYS) ? 'S' : '-',
                   (ff_info.fattrib & AM_ARC) ? 'A' : '-');
            printf("[size]: %lu bytes ", ff_info.fsize);
            printf("[date]: %u-%02u-%02u %02u:%02u\n",
                   (ff_info.fdate >> 9) + 1980, ff_info.fdate >> 5 & 15, ff_info.fdate & 31,
                   ff_info.ftime >> 11, ff_info.ftime >> 5 & 63);
        break;
        case FR_NO_FILE:
        case FR_NO_PATH:
            printf("\"%s\" is not exist.\n", argv[1]);
        break;
        default:
            printf("An error occured. (%d)\n", ff_res);
    }
}

void tinysh_launch() {
    char type_res[MAX_CMD_LEN], type_ch;
    uint8_t type_len, fs_init_state = 0;
    FATFS fs;

    tinysh_welcome();
    fs_init_state = tinysh_mount_fs(&fs);
    // register internal cmd
    tinysh_register("help", "default help info", tinysh_help);
    tinysh_register("history", "print history list", tinysh_history_list);
    if(fs_init_state == (uint8_t)0) {
        // ls -> fatfs
        // pwd -> fatfs
        tinysh_register("file", "print file info", tinysh_fat32_file_cmd);
    }

    while(1) {
        printf("tinysh > ");
        type_len = 0;

        do {
            type_ch = getchar();
            if((type_ch >= 'a' && type_ch <= 'z') || (type_ch >= 'A' && type_ch <= 'Z') ||
               (type_ch >= '0' && type_ch <= '9') || type_ch == ' ' || type_ch == '.') {
                if(type_len == MAX_CMD_LEN) break;
                putchar(type_ch);
                type_res[type_len++] = type_ch;
            } else if(type_ch == '\b' || type_ch == (char) 127){
                if(type_len == 0) continue;
                printf("\b \b");
                type_res[type_len--] = 0;
            } else if(type_ch == (char) 9) { // tab
                printf("tab\n");
                // tinysh_search_cmd(type_res, type_len);
            }

        } while(type_ch != '\n' && type_ch != '\r');
        putchar('\n');
        
        type_res[type_len] = 0;
        if(sh_history_idx < MAX_CMD_HIST) strcpy(sh_history_table[sh_history_idx++], type_res);
        else {
            for(uint8_t i = 1; i < MAX_CMD_HIST; ++i) {
                strcpy(sh_history_table[i-1], sh_history_table[i]);
            }
            strcpy(sh_history_table[sh_history_idx-1], type_res);
        }

        tinysh_parse_and_exec(type_res);
    }

}
