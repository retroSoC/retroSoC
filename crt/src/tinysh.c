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
// app
static char fat32_pwd[MAX_PATH_LEN];


uint8_t tinysh_register(char *name, char *info, uint8_t batch, void *handler) {
    if(!name || !handler || !strlen(name)) return 1;
    if(sh_cmd_len == MAX_CMD_NUM) return 1;

    for(uint8_t i = 0; i < sh_cmd_len; ++i) {
        if(strcmp(name, sh_cmd_list[i].name) == 0) return 1;
    }

    tinysh_cmd_t tmp = {name, info, batch, handler};
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
    uint8_t tmp_len = 0, escape_char = 0;

    for(uint8_t i = 0; i < MAX_CMD_LEN; ++i) {
        if(cmd[i] == '"') {
            if(escape_char == 0) escape_char = 1;
            else escape_char = 0;
        } else if(cmd[i] == ' ' && escape_char == 0) {
            sub_cmd[tmp_len] = 0;
            // printf("sub cmd: %s\n", sub_cmd);
            strcpy(sh_argv[sh_argc], sub_cmd);
            ++sh_argc;
            tmp_len = 0;
        } else {
            sub_cmd[tmp_len++] = cmd[i];
        }
    }
    sub_cmd[tmp_len] = 0;
    // printf("sub cmd: %s\n", sub_cmd);
    strcpy(sh_argv[sh_argc], sub_cmd);
    ++sh_argc;

    strcpy(sh_argv[sh_argc], NULL);

    // printf("argc: %d\nargv:", sh_argc);
    // for(uint8_t i = 0; i <= sh_argc; ++i) {
    //     printf(" %s", sh_argv[i] == NULL ? "NULL" : sh_argv[i]);
    // }
    // printf("\n");

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

    if(!is_find) printf("cmd: [%s] not found\n", sh_argv[0]);
}

static void tinysh_help() {
    for(uint8_t i = 0; i < sh_cmd_len; ++i) {
        printf("cmd: %8s info: %s\n", sh_cmd_list[i].name, sh_cmd_list[i].info);
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
    strcpy(fat32_pwd, "/");
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


void tinysh_fat32_ls_cmd(int argc, char **argv) {
    char dir_path[MAX_PATH_LEN];

    if(argc == 1) strcpy(dir_path, fat32_pwd);
    else if(argc == 2) {
        strcpy(dir_path, argv[1]);
        strcpy(fat32_pwd, argv[1]);
    } else {
        printf("[error] argv:");
        for(uint8_t i = 0; i < argc; ++i) {
            printf(" %s", argv[i]);
        }
        printf("\n");
        return;
    }

    FRESULT ff_res;
    DIR ff_dir;
    FILINFO ff_info;
    int file_num, dir_num;

    ff_res = f_opendir(&ff_dir, dir_path);
    if (ff_res == FR_OK) {
        file_num = dir_num = 0;
        while(1) {
            ff_res = f_readdir(&ff_dir, &ff_info);     /* Read a directory item */
            if (ff_info.fname[0] == 0) break;          /* Error or end of ff_dir */
            if (ff_info.fattrib & AM_DIR) {            /* It is a directory */
                printf("   <DIR>   %s/\n", ff_info.fname);
                ++dir_num;
            } else {                               /* It is a file */
                printf("%10u %s\n", ff_info.fsize, ff_info.fname);
                ++file_num;
            }
        }
        f_closedir(&ff_dir);
        printf("%d dirs, %d files.\n", dir_num, file_num);
    } else {
        printf("Failed to open \"%s\". (%u)\n", dir_path, ff_res);
    }
}

FRESULT tinysh_fat32_lsr_cmd(int argc, char **argv) {
    (void) argv;

    if(argc != 1) {
        printf("lsr cmd param error\n");
        return FR_OK;
    }

    FRESULT ff_res;
    DIR ff_dir;
    UINT i;
    FILINFO ff_info;

    ff_res = f_opendir(&ff_dir, fat32_pwd);                  /* Open the directory */
    if (ff_res == FR_OK) {
        while(1) {
            ff_res = f_readdir(&ff_dir, &ff_info);            /* Read a directory item */
            if (ff_info.fname[0] == 0) break;                 /* Break on error or end of ff_dir */
            if (ff_info.fattrib & AM_DIR) {                   /* The item is a directory */
                i = strlen(fat32_pwd);
                sprintf(&fat32_pwd[i], "/%s", ff_info.fname);
                ff_res = tinysh_fat32_lsr_cmd(argc, argv);    /* Enter the directory */
                if (ff_res != FR_OK) break;
                fat32_pwd[i] = 0;
            } else {                                         /* The item is a file. */
                printf("%s/%s\n", fat32_pwd, ff_info.fname);
            }
        }
        f_closedir(&ff_dir);
    }
    return ff_res;
}

void tinysh_fat32_cd_cmd(int argc, char **argv) {
    if(argc != 2) {
        printf("cd cmd param error\n");
        return;
    }

    FRESULT ff_res;
    TCHAR dir_path[MAX_PATH_LEN];
    if(strcmp(argv[1], "..") == 0) {
        if(strcmp(fat32_pwd, "/") == 0) return;

        remove_suffix(dir_path, fat32_pwd, '/');
    } else if(argv[1][0] == '/') strcpy(dir_path, argv[1]); // abs path
    else {
        // rel path
        strcpy(dir_path, fat32_pwd);
        strcat(dir_path, "/");
        strcat(dir_path, argv[1]);
    }

    ff_res = f_chdir(dir_path);
    if(ff_res != FR_OK) {
        printf("ch cmd exec error\n");
    } else strcpy(fat32_pwd, dir_path);

}

void tinysh_fat32_pwd_cmd(int argc, char **argv) {
    (void) argc;
    (void) argv;

    FRESULT ff_res;
    TCHAR dir_path[MAX_PATH_LEN];

    ff_res = f_getcwd(dir_path, MAX_PATH_LEN);
    if(ff_res == FR_OK) {
        printf("%s\n", dir_path);
        strcpy(fat32_pwd, dir_path);
    }
}

void tinysh_fat32_find_cmd(int argc, char **argv) {
    if(argc != 2 && argc != 3) {
        printf("find cmd param error\n");
        return;
    }

    FRESULT ff_res;  /* Return value */
    DIR ff_dir;      /* Directory object */
    FILINFO ff_info; /* File information */

    // support blob oper
    if(argc == 2) {
        ff_res = f_findfirst(&ff_dir, &ff_info, fat32_pwd, argv[1]);
    } else if(argc == 3) {
        ff_res = f_findfirst(&ff_dir, &ff_info, argv[1], argv[2]);
    }

    while (ff_res == FR_OK && ff_info.fname[0]) {     /* Repeat while an item is found */
        printf("%s\n", ff_info.fname);                /* Print the object name */
        ff_res = f_findnext(&ff_dir, &ff_info);       /* Search for next item */
    }

    f_closedir(&ff_dir);
}

void tinysh_fat32_file_cmd(int argc, char **argv) {

    if(argc != 2) {
        printf("file cmd param error\n");
        return;
    }

    // printf("file name: %s\n", argv[1]);

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
    uint8_t type_len;

    tinysh_welcome();
    uint8_t fs_init_state = 0;
    FATFS fs;
    fs_init_state = tinysh_mount_fs(&fs);
    // register internal cmd
    tinysh_register("help", "help info", (uint8_t)0, tinysh_help);
    tinysh_register("history", "print history list", (uint8_t)0, tinysh_history_list);
    if(fs_init_state == (uint8_t)0) {
        tinysh_register("ls", "list directory contents", (uint8_t)0, tinysh_fat32_ls_cmd);
        tinysh_register("lsr", "list directory contents recursively", (uint8_t)0, tinysh_fat32_lsr_cmd);
        tinysh_register("cd", "change directory", (uint8_t)0, tinysh_fat32_cd_cmd);
        tinysh_register("pwd", "print current directory", (uint8_t)0, tinysh_fat32_pwd_cmd);
        tinysh_register("find", "search files in directory", (uint8_t)0, tinysh_fat32_find_cmd);
        tinysh_register("file", "print file info", (uint8_t)0, tinysh_fat32_file_cmd);
    }

    while(1) {
        printf("tinysh > ");
        type_len = 0;

        do {
            type_ch = getchar();
            if((type_ch >= 'a' && type_ch <= 'z') || (type_ch >= 'A' && type_ch <= 'Z') ||
               (type_ch >= '0' && type_ch <= '9') || type_ch == ' ' || type_ch == '.' ||
                type_ch == '/' || type_ch == '_' || type_ch == '"' || type_ch == '/' ||
                type_ch == '*' || type_ch == '-') {
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

void tinysh_batch_run() {
    for(uint8_t i = 0; i < sh_cmd_len; ++i) {
        if(sh_cmd_list[i].batch == (uint8_t)1) sh_cmd_list[i].handler(0, NULL);
    }
}
