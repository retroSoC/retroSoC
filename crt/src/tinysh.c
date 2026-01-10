#include <firmware.h>
#include <tinyprint.h>
#include <tinyprintf.h>
#include <tinylib.h>
#include <tinystring.h>
#include <tinysh.h>
#include <tinylcd.h>
#include <tinytim.h>
#include <ff.h>
#include <video_player.h>
#include <core_portme.h>
// #include <lvgl.h>
// #include <lv_port_disp.h>
#ifdef IP_MDD
#include <userip.h>
#endif


static char sh_argv_buf[MAX_CMD_ARGC][MAX_CMD_LEN]; // NOTE: clear
static char *sh_argv[MAX_CMD_ARGC];
static uint8_t sh_argc;
static tinysh_cmd_t sh_cmd_list[MAX_CMD_NUM];
static uint8_t sh_cmd_len;
static char sh_history_table[MAX_CMD_HIST][MAX_CMD_LEN];
static uint8_t sh_history_idx;
// app
static char fat32_pwd[MAX_PATH_LEN];
static char lsr_pwd[MAX_PATH_LEN];
static uint8_t lsr_first;
static uint8_t file_buffer[MAX_BUFFER_LEN];


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
    trim_whitespace(cmd);
    // printf("split original cmd: ==%s==\n", cmd);
    if (strlen(cmd) == 0) return 1;

    sh_argc = 0;
    char sub_cmd[MAX_CMD_LEN];
    uint8_t tmp_len = 0, escape_char = 0, cmd_len = strlen(cmd);
    for(uint8_t i = 0; i < cmd_len; ++i) {
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
        // printf(" %s", sh_argv[i] == NULL ? "NULL" : sh_argv[i]);
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
            lsr_first = 1;
            break;
        }
    }

    if(!is_find) printf("cmd: [%s] not found\n", sh_argv[0]);
}

void tinysh_load_file(char *path, uint8_t head) {
    FIL ff_obj;
    FRESULT ff_res;
    UINT br;
    FSIZE_t rd_len = 0;

    // printf("path: %s\n", path);
    ff_res = f_open(&ff_obj, path, FA_READ);
    if (ff_res != FR_OK) {
        f_close(&ff_obj);
        return;
    }

    // printf("open file is right!\n");
    printf("stat: %d\n", ff_obj.obj.stat);
    printf("size: %d bytes\n", ff_obj.obj.objsize);

    if(head) rd_len = 64;
    else {
        if(ff_obj.obj.objsize > MAX_BUFFER_LEN) {
            printf("file size is larger than the buffer size\n");
            f_close(&ff_obj);
            return;
        }
        rd_len = ff_obj.obj.objsize;
    }

    ff_res = f_read(&ff_obj, file_buffer, rd_len, &br);
    if(ff_res != FR_OK) printf("br: %d\n", br);
    f_close(&ff_obj);
}

static void tinysh_help() {
    for(uint8_t i = 0; i < sh_cmd_len; ++i) {
        printf("cmd: %-10s --- %s\n", sh_cmd_list[i].name, sh_cmd_list[i].info);
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
    lsr_first = 1;
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

    printf("argc: %d ff_pwd: %s\n", argc, fat32_pwd);
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

    if(lsr_first) {
        strcpy(lsr_pwd, fat32_pwd);
        lsr_first = 0;
    }

    ff_res = f_opendir(&ff_dir, lsr_pwd);                  /* Open the directory */
    if (ff_res == FR_OK) {
        while(1) {
            ff_res = f_readdir(&ff_dir, &ff_info);            /* Read a directory item */
            if (ff_info.fname[0] == 0) break;                 /* Break on error or end of ff_dir */
            if (ff_info.fattrib & AM_DIR) {                   /* The item is a directory */
                i = strlen(lsr_pwd);
                sprintf(&lsr_pwd[i], "/%s", ff_info.fname);
                ff_res = tinysh_fat32_lsr_cmd(argc, argv);    /* Enter the directory */
                if (ff_res != FR_OK) break;
                lsr_pwd[i] = 0;
            } else {                                         /* The item is a file. */
                printf("%s/%s\n", lsr_pwd, ff_info.fname);
            }
        }
        f_closedir(&ff_dir);
    }
    return ff_res;
}

void tinysh_fat32_cd_cmd(int argc, char **argv) {
    if(argc != 2) {
        printf("[cd] cmd param error\n");
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

void tinysh_fat32_mv_cmd(int argc, char **argv) {
    if(argc != 3) {
        printf("[mv] cmd param error\n");
        return;
    }

    FRESULT ff_res;
    ff_res = f_rename(argv[1], argv[2]);
    if(ff_res != FR_OK) printf("error: %d\n", ff_res);
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

void tinysh_fat32_mkdir_cmd(int argc, char **argv) {
    if(argc != 2) {
        printf("[mkdir] cmd param error\n");
        return;
    }

    FRESULT ff_res;
    ff_res = f_mkdir(argv[1]);
    if(ff_res != FR_OK) printf("error: %d\n", ff_res);
}

void tinysh_fat32_rm_cmd(int argc, char **argv) {
    if(argc != 2) {
        printf("[rm] cmd param error\n");
        return;
    }

    FRESULT ff_res;
    ff_res = f_unlink(argv[1]);
    if(ff_res != FR_OK) printf("error: %d\n", ff_res);
}

void tinysh_fat32_chmod_cmd(int argc, char **argv) {
    if(argc != 2) {
        printf("[chmod] cmd param error\n");
        return;
    }

    FRESULT ff_res;
    ff_res = f_chmod(argv[1], AM_RDO, AM_RDO);
    if(ff_res != FR_OK) printf("error: %d\n", ff_res);
}

void tinysh_fat32_touch_cmd(int argc, char **argv) {
    if(argc != 8) {
        printf("[touch] cmd param error\n");
        return;
    }

    FRESULT ff_res;
    FILINFO ff_info;
    // touch file year month day hour min sec
    ff_info.fdate = (WORD)(((atoi(argv[2]) - 1980) * 512U) | atoi(argv[3]) * 32U | atoi(argv[4]));
    ff_info.ftime = (WORD)(atoi(argv[5]) * 2048U | atoi(argv[6]) * 32U | atoi(argv[7]) / 2U);
#if FF_FS_CRTIME
    ff_info.crdate = 0;   /* Do not change created time in this code */
#endif

    ff_res = f_utime(argv[1], &ff_info);
    if(ff_res != FR_OK) printf("error: %d\n", ff_res);
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
            printf("[date]: %u-%02u-%02u %02u:%02u%02u\n",
                   (ff_info.fdate >> 9) + 1980, ff_info.fdate >> 5 & 15, ff_info.fdate & 31,
                   ff_info.ftime >> 11, ff_info.ftime >> 5 & 63, ff_info.ftime * 2);
        break;
        case FR_NO_FILE:
        case FR_NO_PATH:
            printf("\"%s\" is not exist.\n", argv[1]);
        break;
        default:
            printf("An error occured. (%d)\n", ff_res);
    }
}

void tinysh_fat32_write_cmd(int argc, char **argv) {
    // write test.txt asdf.txtxt
    if(argc != 3) {
        printf("[write] cmd param error\n");
        return;
    }

    FIL ff_obj;
    FRESULT ff_res;
    UINT ff_num;
    ff_res = f_open(&ff_obj, argv[1], FA_WRITE | FA_CREATE_ALWAYS);
    if(ff_res == FR_OK) {
        ff_res = f_write(&ff_obj, argv[2], strlen(argv[2]), &ff_num);
        if(ff_res != FR_OK) printf("error: %d\n", ff_res);
    } else {
        printf("error: %d\n", ff_res);
    }
    f_close(&ff_obj);
}

void tinysh_fat32_cat_cmd(int argc, char **argv) {
    if(argc != 2) {
        printf("[cat] cmd param error\n");
        return;
    }

    tinysh_load_file(argv[1], (uint8_t)1);
    printf("file header:\n");
    for(uint8_t i = 0; i < 4; ++i) {
        for(uint8_t j = 0; j < 16; ++j) {
            printf("%02x", file_buffer[16*i+j]);
            if(j <= 14) printf(" ");
        }
        printf("\n");
    }
}

void tinysh_fat32_df_cmd(int argc, char **argv) {
    (void) argv;
    if(argc != 1) {
        printf("[df] cmd param error\n");
        return;
    }

    FATFS *fs;
    FRESULT ff_res;
    DWORD free_clust, free_sect, total_sect;
    /* Get volume information and free clusters of drive 1 */
    ff_res = f_getfree("0:", &free_clust, &fs);
    if (ff_res != FR_OK) {
        printf("error: %d\n", ff_res);
        return;
    }

    /* Get total sectors and free sectors */
    total_sect = (fs->n_fatent - 2) * fs->csize;
    free_sect = free_clust * fs->csize;

    /* Print the free space (assuming 512 bytes/sector) */
    printf("%10lu MiB total drive space.\n%10lu MiB available.\n", total_sect / 2 / 1024, free_sect / 2 / 1024);
}

void tinysh_fat32_fatlabel_cmd(int argc, char **argv) {
    if(argc != 1 && argc != 2) {
        printf("[fatlabel] cmd param error\n");
        return;
    }

    TCHAR label[24];
    DWORD vsn;
    FRESULT ff_res;
    if(argc == 1) {
        ff_res = f_getlabel("", label, &vsn);
        if (ff_res != FR_OK) printf("error: %d\n", ff_res);
        printf("Volume Label: %s\n", label);
        printf("Volume Serial Number: %lu\n", (unsigned long)vsn);
    } else if(argc == 2) {
        ff_res = f_setlabel(argv[1]);
        if(ff_res != FR_OK) printf("error: %d\n", ff_res);
    }
}

void tinysh_app_image_cmd(int argc, char **argv) {
    // image: -i -m[0] file.bin
    // uint8_t is_info = 1, frame = 0;
    if(argc != 2) {
        printf("[image] cmd param error\n");
        return;
    }

    // for(uint8_t i = 0; i < 64; ++i) printf("file_buffer: %x\n", file_buffer[i]);

    static uint8_t image_is_init = 0;
    if(image_is_init == 0) {
        tinysh_load_file(argv[1], (uint8_t)0);
        image_is_init = 1;
    }

    VideoHeader_t* videoHeader = (VideoHeader_t *)file_buffer;
    printf("================================\n");
    printf("       image bin file info      \n");
    printf("width:       %d\n", videoHeader->width);
    printf("height:      %d\n", videoHeader->height);
    printf("frame count: %d\n", videoHeader->frame_count);
    printf("================================\n");

    uint32_t* ptr = (uint32_t*)(file_buffer + 16);
    uint32_t delta = videoHeader->width * videoHeader->height / 2;
    uint8_t idx = 0;
    while(1) {
        lcd_fill_image(0, 0, videoHeader->width, videoHeader->height, ptr);
        delay_ms(3000);

        if(idx == 3) {
            idx = 0;
            ptr = (uint32_t*)(file_buffer + 16);
        } else {
            ++idx;
            ptr += delta;
        }
    }

}

// video -i info
void tinysh_app_video_cmd(int argc, char **argv) {
    (void)argc;
    (void)argv;
}

// audio -i info
void tinysh_app_audio_cmd(int argc, char **argv) {
    (void)argc;
    (void)argv;
}


// val * 1000 / CPU_FREQ / 1000 / 1000
// uint32_t my_get_millis(void) {
//     return reg_tim1_val / CPU_FREQ / 1000;
// }

void tinysh_app_lvgl_cmd(int argc, char **argv) {
    (void)argc;
    (void)argv;

    // lv_init();
    // tim1_init();
    // lv_tick_set_cb(my_get_millis);

    // lv_port_disp_init();

    // lv_obj_t *label = lv_label_create(lv_scr_act());
    // lv_label_set_text(label,"Hello maksyuki!!!");
    // lv_obj_center(label);

    // while(1) {
    //     lv_timer_handler();
    //     delay_ms(5);
    //     printf("hello\n");
    // }
}

void tinysh_app_arduboy_cmd(int argc, char **argv) {
    (void)argc;
    (void)argv;
}

void tinysh_app_nes_cmd(int argc, char **argv) {
    (void)argc;
    (void)argv;
}

void tinysh_app_coremark_cmd(int argc, char **argv) {
    (void)argc;
    (void)argv;
    core_main();
}

#ifdef IP_MDD
void tinysh_app_userip_cmd(int argc, char **argv) {
    if(argc != 1 && argc != 2) {
        printf("[userip] cmd param error\n");
        return;
    }

    if(argc == 1) {
        printf("current user ip id: %03d\n", reg_sysctrl_ipsel);
        userip_main(0, NULL);
    } else if(argc == 2) {
        int16_t user_id = atoi(argv[1]);
        if(user_id >= 0 && user_id <= 255) {
            printf("switch to user ip id to [%03d...]\n", user_id);
            reg_sysctrl_ipsel = (uint8_t)user_id;
            userip_main(user_id, NULL); // HACK:
        } else {
            printf("error use id: %d\n", user_id);
            return;
        }
    }
    // userip: list all info/current id
}
#endif

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
    tinysh_register("coremark", "coremark test", (uint8_t)0, tinysh_app_coremark_cmd);
#ifdef IP_MDD
    tinysh_register("userip", "run user ip program", (uint8_t)0, tinysh_app_userip_cmd);
#endif
    if(fs_init_state == (uint8_t)0) {
        tinysh_register("ls", "list directory contents", (uint8_t)0, tinysh_fat32_ls_cmd);
        tinysh_register("lsr", "list directory contents recursively", (uint8_t)0, tinysh_fat32_lsr_cmd);
        tinysh_register("cd", "change directory", (uint8_t)0, tinysh_fat32_cd_cmd);
        tinysh_register("mv", "move/remove files", (uint8_t)0, tinysh_fat32_mv_cmd);
        tinysh_register("pwd", "print current directory", (uint8_t)0, tinysh_fat32_pwd_cmd);
        tinysh_register("mkdir", "make directories", (uint8_t)0, tinysh_fat32_mkdir_cmd);
        tinysh_register("rm", "remove files or directories", (uint8_t)0, tinysh_fat32_rm_cmd);
        tinysh_register("chmod", "change file mode bits", (uint8_t)0, tinysh_fat32_chmod_cmd);
        tinysh_register("touch", "change file timestamps", (uint8_t)0, tinysh_fat32_touch_cmd);
        tinysh_register("find", "search files in directory", (uint8_t)0, tinysh_fat32_find_cmd);
        tinysh_register("file", "print file info", (uint8_t)0, tinysh_fat32_file_cmd);
        tinysh_register("write", "write stirng to file", (uint8_t)0, tinysh_fat32_write_cmd);
        tinysh_register("cat", "concatenate file(s) to standard output", (uint8_t)0, tinysh_fat32_cat_cmd);
        tinysh_register("df", "report file system disk space usage", (uint8_t)0, tinysh_fat32_df_cmd);
        tinysh_register("fatlabel", "set/get filesystem label or volume ID", (uint8_t)0, tinysh_fat32_fatlabel_cmd);
        tinysh_register("image", "image viewer", (uint8_t)0, tinysh_app_image_cmd);
        tinysh_register("video", "video player", (uint8_t)0, tinysh_app_video_cmd);
        tinysh_register("audio", "audio player", (uint8_t)0, tinysh_app_audio_cmd);
        tinysh_register("lvgl", "show lvgl components", (uint8_t)0, tinysh_app_lvgl_cmd);
        tinysh_register("arduboy", "run arduboy", (uint8_t)0, tinysh_app_arduboy_cmd);
        tinysh_register("nes", "run nes simulator", (uint8_t)0, tinysh_app_nes_cmd);
        printf("register cmd num: %d\n", sh_cmd_len);
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
        // printf("ff_pwd: %s\n", fat32_pwd);
    }
}

void tinysh_batch_run() {
    for(uint8_t i = 0; i < sh_cmd_len; ++i) {
        if(sh_cmd_list[i].batch == (uint8_t)1) sh_cmd_list[i].handler(0, NULL);
    }
}
