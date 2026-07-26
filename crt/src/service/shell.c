#include <retrosoc/core/soc.h>
#include <retrosoc/lib/console.h>
#include <retrosoc/lib/printf.h>
#include <retrosoc/lib/stdlib.h>
#include <retrosoc/lib/string.h>
#include <retrosoc/service/shell.h>
#include <retrosoc/hal/lcd.h>
#include <retrosoc/hal/timer.h>
#include <ff.h>
#include <retrosoc/media/video_player.h>
#include <core_portme.h>
// #include <lvgl.h>
// #include <lv_port_disp.h>
#include <userip.h>

static char sh_argv_buf[RS_SHELL_MAX_ARGC][RS_SHELL_MAX_COMMAND_LENGTH + 1U];
static char *sh_argv[RS_SHELL_MAX_ARGC + 1U];
static uint8_t sh_argc;
static rs_shell_command_t sh_cmd_list[RS_SHELL_MAX_COMMANDS];
static uint8_t sh_cmd_len;
static char sh_history_table[RS_SHELL_MAX_HISTORY][RS_SHELL_MAX_COMMAND_LENGTH + 1U];
static uint8_t sh_history_idx;
static char fat32_pwd[RS_SHELL_MAX_PATH];
static char lsr_pwd[RS_SHELL_MAX_PATH];
static uint32_t file_buffer_words[RS_SHELL_MAX_BUFFER / sizeof(uint32_t)];
static uint8_t *const file_buffer = (uint8_t *)file_buffer_words;

rs_status_t rs_shell_register(const char *name, const char *info, bool batch,
                              rs_shell_handler_t handler) {
    if ((name == NULL) || (handler == NULL) || (name[0] == '\0')) {
        return RS_EINVAL;
    }
    if (sh_cmd_len >= RS_SHELL_MAX_COMMANDS) {
        return RS_ENOSPC;
    }
    for (uint8_t index = 0U; index < sh_cmd_len; ++index) {
        if (strcmp(name, sh_cmd_list[index].name) == 0) {
            return RS_EINVAL;
        }
    }

    sh_cmd_list[sh_cmd_len] = (rs_shell_command_t){name, info, batch, handler};
    ++sh_cmd_len;
    return RS_OK;
}

static rs_status_t rs_shell_split_command(char *command) {
    char *cursor;

    if (command == NULL) {
        return RS_EINVAL;
    }
    rs_trim_whitespace(command);
    if (command[0] == '\0') {
        return RS_EINVAL;
    }

    sh_argc = 0U;
    cursor = command;
    while (*cursor != '\0') {
        char *dst;
        size_t length = 0U;
        bool quoted = false;

        while ((*cursor == ' ') || (*cursor == '\t')) {
            ++cursor;
        }
        if (*cursor == '\0') {
            break;
        }
        if (sh_argc >= RS_SHELL_MAX_ARGC) {
            return RS_ENOSPC;
        }

        dst = sh_argv_buf[sh_argc];
        while (*cursor != '\0') {
            if (*cursor == '"') {
                quoted = !quoted;
                ++cursor;
                continue;
            }
            if (!quoted && ((*cursor == ' ') || (*cursor == '\t'))) {
                break;
            }
            if (length >= RS_SHELL_MAX_COMMAND_LENGTH) {
                return RS_ENOSPC;
            }
            dst[length++] = *cursor++;
        }
        if (quoted) {
            return RS_EFORMAT;
        }
        dst[length] = '\0';
        sh_argv[sh_argc] = dst;
        ++sh_argc;
    }

    sh_argv[sh_argc] = NULL;
    return (sh_argc == 0U) ? RS_EINVAL : RS_OK;
}

static void rs_shell_parse_and_exec(char *command) {
    const rs_status_t split_status = rs_shell_split_command(command);

    if (split_status != RS_OK) {
        printf("shell input error: %d\n", split_status);
        return;
    }

    for (uint8_t index = 0U; index < sh_cmd_len; ++index) {
        if (strcmp(sh_argv[0], sh_cmd_list[index].name) == 0) {
            sh_cmd_list[index].handler((int)sh_argc, sh_argv);
            return;
        }
    }
    printf("cmd: [%s] not found\n", sh_argv[0]);
}

static rs_status_t rs_shell_load_file(const char *path, bool header_only, uint32_t *bytes_read) {
    FIL ff_obj;
    FRESULT ff_res;
    UINT read_count = 0U;
    FSIZE_t rd_len = 0;

    if ((path == NULL) || (bytes_read == NULL)) {
        return RS_EINVAL;
    }
    *bytes_read = 0U;
    ff_res = f_open(&ff_obj, path, FA_READ);
    if (ff_res != FR_OK) {
        return RS_EIO;
    }

    // printf("open file is right!\n");
    printf("stat: %d\n", ff_obj.obj.stat);
    printf("size: %d bytes\n", ff_obj.obj.objsize);

    if (header_only) {
        rd_len = (ff_obj.obj.objsize < 64U) ? ff_obj.obj.objsize : 64U;
    } else {
        if (ff_obj.obj.objsize > RS_SHELL_MAX_BUFFER) {
            printf("file size is larger than the buffer size\n");
            f_close(&ff_obj);
            return RS_ENOSPC;
        }
        rd_len = ff_obj.obj.objsize;
    }

    ff_res = f_read(&ff_obj, file_buffer, rd_len, &read_count);
    f_close(&ff_obj);
    if ((ff_res != FR_OK) || (read_count != rd_len)) {
        return RS_EIO;
    }
    *bytes_read = read_count;
    return RS_OK;
}

static void rs_shell_help(int argc, char **argv) {
    (void)argc;
    (void)argv;
    for (uint8_t i = 0U; i < sh_cmd_len; ++i) {
        printf("cmd: %-10s --- %s\n", sh_cmd_list[i].name, sh_cmd_list[i].info);
    }
}

static void rs_shell_history_list(int argc, char **argv) {
    (void)argc;
    (void)argv;
    for (uint8_t i = 0U; i < sh_history_idx; ++i) {
        printf("%3d %s\n", i, sh_history_table[i]);
    }
}

static void rs_shell_welcome(void) {
    printf("================================\n");
    printf("        retroSoC Shell          \n");
    printf("================================\n");
}

void rs_shell_init(void) {
    sh_cmd_len = 0;
    sh_history_idx = 0;
    for (uint8_t i = 0U; i < RS_SHELL_MAX_ARGC; ++i) {
        sh_argv[i] = sh_argv_buf[i];
    }
    sh_argv[RS_SHELL_MAX_ARGC] = NULL;
    (void)rs_strlcpy(fat32_pwd, "/", sizeof(fat32_pwd));
}

static rs_status_t rs_shell_mount_fs(FATFS *fs) {
    FRESULT ff_res;
    ff_res = f_mount(fs, "0:", 1);
    switch (ff_res) {
    case FR_NO_FILESYSTEM:
        printf("[fatfs] no filesystem\n");
        return RS_EIO;
    case FR_OK:
        printf("[fatfs] mount done\n");
        return RS_OK;
    default:
        printf("[fatfs] filesystem mount fail\n");
        return RS_EIO;
    }
}

static void rs_shell_fat32_ls_cmd(int argc, char **argv) {
    char dir_path[RS_SHELL_MAX_PATH];

    printf("argc: %d ff_pwd: %s\n", argc, fat32_pwd);
    if (argc == 1) {
        (void)rs_strlcpy(dir_path, fat32_pwd, sizeof(dir_path));
    } else if (argc == 2) {
        if (rs_strlcpy(dir_path, argv[1], sizeof(dir_path)) >= sizeof(dir_path)) {
            printf("path is too long\n");
            return;
        }
        (void)rs_strlcpy(fat32_pwd, dir_path, sizeof(fat32_pwd));
    } else {
        printf("[error] argv:");
        for (uint8_t i = 0; i < argc; ++i) {
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
        for (;;) {
            ff_res = f_readdir(&ff_dir, &ff_info); /* Read a directory item */
            if (ff_res != FR_OK) {
                printf("directory read failed: %d\n", ff_res);
                break;
            }
            if (ff_info.fname[0] == 0) {
                break;
            }
            if (ff_info.fattrib & AM_DIR) { /* It is a directory */
                printf("   <DIR>   %s/\n", ff_info.fname);
                ++dir_num;
            } else { /* It is a file */
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

static FRESULT rs_shell_fat32_lsr_walk(void) {
    FRESULT ff_res;
    DIR ff_dir;
    UINT i;
    FILINFO ff_info;

    ff_res = f_opendir(&ff_dir, lsr_pwd); /* Open the directory */
    if (ff_res == FR_OK) {
        for (;;) {
            ff_res = f_readdir(&ff_dir, &ff_info); /* Read a directory item */
            if ((ff_res != FR_OK) || (ff_info.fname[0] == 0)) {
                break;
            }
            if (ff_info.fattrib & AM_DIR) { /* The item is a directory */
                i = strlen(lsr_pwd);
                if ((i + 1U + strlen(ff_info.fname)) >= sizeof(lsr_pwd)) {
                    ff_res = FR_INVALID_NAME;
                    break;
                }
                (void)rs_strlcat(lsr_pwd, "/", sizeof(lsr_pwd));
                (void)rs_strlcat(lsr_pwd, ff_info.fname, sizeof(lsr_pwd));
                ff_res = rs_shell_fat32_lsr_walk(); /* Enter the directory */
                if (ff_res != FR_OK)
                    break;
                lsr_pwd[i] = 0;
            } else { /* The item is a file. */
                printf("%s/%s\n", lsr_pwd, ff_info.fname);
            }
        }
        f_closedir(&ff_dir);
    }
    return ff_res;
}

static void rs_shell_fat32_lsr_cmd(int argc, char **argv) {
    FRESULT ff_res;

    (void)argv;
    if (argc != 1) {
        printf("lsr cmd param error\n");
        return;
    }
    (void)rs_strlcpy(lsr_pwd, fat32_pwd, sizeof(lsr_pwd));
    ff_res = rs_shell_fat32_lsr_walk();
    if (ff_res != FR_OK) {
        printf("lsr failed: %d\n", ff_res);
    }
}

static void rs_shell_fat32_cd_cmd(int argc, char **argv) {
    if (argc != 2) {
        printf("[cd] cmd param error\n");
        return;
    }

    FRESULT ff_res;
    TCHAR dir_path[RS_SHELL_MAX_PATH];
    if (strcmp(argv[1], "..") == 0) {
        if (strcmp(fat32_pwd, "/") == 0)
            return;

        rs_remove_suffix(dir_path, sizeof(dir_path), fat32_pwd, '/');
    } else if (argv[1][0] == '/') {
        if (rs_strlcpy(dir_path, argv[1], sizeof(dir_path)) >= sizeof(dir_path)) {
            printf("path is too long\n");
            return;
        }
    } else {
        if ((rs_strlcpy(dir_path, fat32_pwd, sizeof(dir_path)) >= sizeof(dir_path)) ||
            (rs_strlcat(dir_path, "/", sizeof(dir_path)) >= sizeof(dir_path)) ||
            (rs_strlcat(dir_path, argv[1], sizeof(dir_path)) >= sizeof(dir_path))) {
            printf("path is too long\n");
            return;
        }
    }

    ff_res = f_chdir(dir_path);
    if (ff_res != FR_OK) {
        printf("ch cmd exec error\n");
    } else {
        (void)rs_strlcpy(fat32_pwd, dir_path, sizeof(fat32_pwd));
    }
}

static void rs_shell_fat32_mv_cmd(int argc, char **argv) {
    if (argc != 3) {
        printf("[mv] cmd param error\n");
        return;
    }

    FRESULT ff_res;
    ff_res = f_rename(argv[1], argv[2]);
    if (ff_res != FR_OK)
        printf("error: %d\n", ff_res);
}

static void rs_shell_fat32_pwd_cmd(int argc, char **argv) {
    (void)argc;
    (void)argv;

    FRESULT ff_res;
    TCHAR dir_path[RS_SHELL_MAX_PATH];

    ff_res = f_getcwd(dir_path, RS_SHELL_MAX_PATH);
    if (ff_res == FR_OK) {
        printf("%s\n", dir_path);
        (void)rs_strlcpy(fat32_pwd, dir_path, sizeof(fat32_pwd));
    }
}

static void rs_shell_fat32_mkdir_cmd(int argc, char **argv) {
    if (argc != 2) {
        printf("[mkdir] cmd param error\n");
        return;
    }

    FRESULT ff_res;
    ff_res = f_mkdir(argv[1]);
    if (ff_res != FR_OK)
        printf("error: %d\n", ff_res);
}

static void rs_shell_fat32_rm_cmd(int argc, char **argv) {
    if (argc != 2) {
        printf("[rm] cmd param error\n");
        return;
    }

    FRESULT ff_res;
    ff_res = f_unlink(argv[1]);
    if (ff_res != FR_OK)
        printf("error: %d\n", ff_res);
}

static void rs_shell_fat32_chmod_cmd(int argc, char **argv) {
    if (argc != 2) {
        printf("[chmod] cmd param error\n");
        return;
    }

    FRESULT ff_res;
    ff_res = f_chmod(argv[1], AM_RDO, AM_RDO);
    if (ff_res != FR_OK)
        printf("error: %d\n", ff_res);
}

static void rs_shell_fat32_touch_cmd(int argc, char **argv) {
    int32_t year;
    int32_t month;
    int32_t day;
    int32_t hour;
    int32_t minute;
    int32_t second;

    if (argc != 8) {
        printf("[touch] cmd param error\n");
        return;
    }
    if ((rs_strtoi32(argv[2], &year) != RS_OK) || (rs_strtoi32(argv[3], &month) != RS_OK) ||
        (rs_strtoi32(argv[4], &day) != RS_OK) || (rs_strtoi32(argv[5], &hour) != RS_OK) ||
        (rs_strtoi32(argv[6], &minute) != RS_OK) || (rs_strtoi32(argv[7], &second) != RS_OK) ||
        (year < 1980) || (year > 2107) || (month < 1) || (month > 12) || (day < 1) || (day > 31) ||
        (hour < 0) || (hour > 23) || (minute < 0) || (minute > 59) || (second < 0) ||
        (second > 59)) {
        printf("[touch] invalid timestamp\n");
        return;
    }

    FRESULT ff_res;
    FILINFO ff_info = {0};
    // touch file year month day hour min sec
    ff_info.fdate =
        (WORD)(((uint32_t)(year - 1980) << 9U) | ((uint32_t)month << 5U) | (uint32_t)day);
    ff_info.ftime =
        (WORD)(((uint32_t)hour << 11U) | ((uint32_t)minute << 5U) | ((uint32_t)second / 2U));
#if FF_FS_CRTIME
    ff_info.crdate = 0; /* Do not change created time in this code */
#endif

    ff_res = f_utime(argv[1], &ff_info);
    if (ff_res != FR_OK)
        printf("error: %d\n", ff_res);
}

static void rs_shell_fat32_find_cmd(int argc, char **argv) {
    if (argc != 2 && argc != 3) {
        printf("find cmd param error\n");
        return;
    }

    FRESULT ff_res;  /* Return value */
    DIR ff_dir;      /* Directory object */
    FILINFO ff_info; /* File information */

    // support blob oper
    if (argc == 2) {
        ff_res = f_findfirst(&ff_dir, &ff_info, fat32_pwd, argv[1]);
    } else if (argc == 3) {
        ff_res = f_findfirst(&ff_dir, &ff_info, argv[1], argv[2]);
    }

    while (ff_res == FR_OK && ff_info.fname[0]) { /* Repeat while an item is found */
        printf("%s\n", ff_info.fname);            /* Print the object name */
        ff_res = f_findnext(&ff_dir, &ff_info);   /* Search for next item */
    }
    if (ff_res == FR_OK) {
        (void)f_closedir(&ff_dir);
    }
}

static void rs_shell_fat32_file_cmd(int argc, char **argv) {
    if (argc != 2) {
        printf("file cmd param error\n");
        return;
    }

    // printf("file name: %s\n", argv[1]);

    FILINFO ff_info;
    FRESULT ff_res;
    ff_res = f_stat(argv[1], &ff_info);

    switch (ff_res) {
    case FR_OK:
        printf("[attr]: %c%c%c%c%c ", (ff_info.fattrib & AM_DIR) ? 'D' : '-',
               (ff_info.fattrib & AM_RDO) ? 'R' : '-', (ff_info.fattrib & AM_HID) ? 'H' : '-',
               (ff_info.fattrib & AM_SYS) ? 'S' : '-', (ff_info.fattrib & AM_ARC) ? 'A' : '-');
        printf("[size]: %lu bytes ", ff_info.fsize);
        printf("[date]: %u-%02u-%02u %02u:%02u%02u\n", (ff_info.fdate >> 9) + 1980,
               ff_info.fdate >> 5 & 15, ff_info.fdate & 31, ff_info.ftime >> 11,
               ff_info.ftime >> 5 & 63, ff_info.ftime * 2);
        break;
    case FR_NO_FILE:
    case FR_NO_PATH:
        printf("\"%s\" is not exist.\n", argv[1]);
        break;
    default:
        printf("An error occured. (%d)\n", ff_res);
    }
}

static void rs_shell_fat32_write_cmd(int argc, char **argv) {
    // write test.txt asdf.txtxt
    if (argc != 3) {
        printf("[write] cmd param error\n");
        return;
    }

    FIL ff_obj;
    FRESULT ff_res;
    UINT ff_num;
    ff_res = f_open(&ff_obj, argv[1], FA_WRITE | FA_CREATE_ALWAYS);
    if (ff_res == FR_OK) {
        ff_res = f_write(&ff_obj, argv[2], strlen(argv[2]), &ff_num);
        if (ff_res != FR_OK)
            printf("error: %d\n", ff_res);
        (void)f_close(&ff_obj);
    } else {
        printf("error: %d\n", ff_res);
    }
}

static void rs_shell_fat32_cat_cmd(int argc, char **argv) {
    uint32_t bytes_read;

    if (argc != 2) {
        printf("[cat] cmd param error\n");
        return;
    }

    if (rs_shell_load_file(argv[1], true, &bytes_read) != RS_OK) {
        printf("[cat] unable to read %s\n", argv[1]);
        return;
    }
    printf("file header:\n");
    for (uint32_t offset = 0U; offset < bytes_read; offset += 16U) {
        const uint32_t line_length = ((bytes_read - offset) < 16U) ? (bytes_read - offset) : 16U;
        for (uint32_t index = 0U; index < line_length; ++index) {
            printf("%02x", file_buffer[offset + index]);
            if (index + 1U < line_length) {
                printf(" ");
            }
        }
        printf("\n");
    }
}

static void rs_shell_fat32_df_cmd(int argc, char **argv) {
    (void)argv;
    if (argc != 1) {
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
    printf("%10lu MiB total drive space.\n%10lu MiB available.\n", total_sect / 2 / 1024,
           free_sect / 2 / 1024);
}

static void rs_shell_fat32_fatlabel_cmd(int argc, char **argv) {
    if (argc != 1 && argc != 2) {
        printf("[fatlabel] cmd param error\n");
        return;
    }

    TCHAR label[24];
    DWORD vsn;
    FRESULT ff_res;
    if (argc == 1) {
        ff_res = f_getlabel("", label, &vsn);
        if (ff_res != FR_OK) {
            printf("error: %d\n", ff_res);
        } else {
            printf("Volume Label: %s\n", label);
            printf("Volume Serial Number: %lu\n", (unsigned long)vsn);
        }
    } else if (argc == 2) {
        ff_res = f_setlabel(argv[1]);
        if (ff_res != FR_OK)
            printf("error: %d\n", ff_res);
    }
}

static void rs_shell_app_image_cmd(int argc, char **argv) {
    // image: -i -m[0] file.bin
    // uint8_t is_info = 1, frame = 0;
    if (argc != 2) {
        printf("[image] cmd param error\n");
        return;
    }

    // for(uint8_t i = 0; i < 64; ++i) printf("file_buffer: %x\n", file_buffer[i]);

    rs_video_info_t video_info;
    uint32_t file_size;
    uint32_t frame_words;

    if (rs_shell_load_file(argv[1], false, &file_size) != RS_OK) {
        printf("[image] unable to read %s\n", argv[1]);
        return;
    }
    if ((rs_video_parse(file_buffer, file_size, &video_info) != RS_OK) ||
        (video_info.width > LCD_W) || (video_info.height > LCD_H)) {
        printf("[image] invalid dimensions\n");
        return;
    }
    frame_words = video_info.frame_size / sizeof(uint32_t);

    printf("================================\n");
    printf("       image bin file info      \n");
    printf("width:       %d\n", video_info.width);
    printf("height:      %d\n", video_info.height);
    printf("frame count: %d\n", video_info.frame_count);
    printf("================================\n");

    for (uint32_t frame = 0U; frame < video_info.frame_count; ++frame) {
        uint32_t *frame_data = file_buffer_words + (video_info.payload_offset / sizeof(uint32_t)) +
                               (frame * frame_words);
        lcd_fill_image(0U, 0U, (uint16_t)video_info.width, (uint16_t)video_info.height, frame_data);
        delay_ms(3000U);
    }
}

// video -i info
static void rs_shell_app_video_cmd(int argc, char **argv) {
    (void)argc;
    (void)argv;
}

// audio -i info
static void rs_shell_app_audio_cmd(int argc, char **argv) {
    (void)argc;
    (void)argv;
}

// val * 1000 / CPU_FREQ / 1000 / 1000
// uint32_t my_get_millis(void) {
//     return reg_tim1_val / CPU_FREQ / 1000;
// }

static void rs_shell_app_lvgl_cmd(int argc, char **argv) {
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

static void rs_shell_app_arduboy_cmd(int argc, char **argv) {
    (void)argc;
    (void)argv;
}

static void rs_shell_app_nes_cmd(int argc, char **argv) {
    (void)argc;
    (void)argv;
}

static void rs_shell_app_coremark_cmd(int argc, char **argv) {
    (void)argc;
    (void)argv;
    core_main();
}

static void rs_shell_app_userip_cmd(int argc, char **argv) {
    if (argc != 1 && argc != 2) {
        printf("[userip] cmd param error\n");
        return;
    }

    if (argc == 1) {
        printf("current user ip id: %03d\n", reg_sysctrl_ipsel);
        userip_main(0, NULL);
    } else if (argc == 2) {
        int32_t user_id;

        if ((rs_strtoi32(argv[1], &user_id) == RS_OK) && (user_id >= 0) && (user_id <= 255)) {
            printf("switch to user ip id to [%03d...]\n", user_id);
            reg_sysctrl_ipsel = (uint8_t)user_id;
            userip_main((int)user_id, NULL); // HACK:
        } else {
            printf("error use id: %d\n", user_id);
            return;
        }
    }
    // userip: list all info/current id
}

void rs_shell_launch(void) {
    char type_res[RS_SHELL_MAX_COMMAND_LENGTH + 1U];
    char type_ch;
    size_t type_len;

    rs_shell_welcome();
    rs_status_t fs_init_state;
    FATFS fs;
    fs_init_state = rs_shell_mount_fs(&fs);
    // register internal cmd
    (void)rs_shell_register("help", "help info", false, rs_shell_help);
    (void)rs_shell_register("history", "print history list", false, rs_shell_history_list);
    (void)rs_shell_register("coremark", "coremark test", false, rs_shell_app_coremark_cmd);
    (void)rs_shell_register("userip", "run user ip program", false, rs_shell_app_userip_cmd);
    if (fs_init_state == RS_OK) {
        (void)rs_shell_register("ls", "list directory contents", false, rs_shell_fat32_ls_cmd);
        (void)rs_shell_register("lsr", "list directory contents recursively", false,
                                rs_shell_fat32_lsr_cmd);
        (void)rs_shell_register("cd", "change directory", false, rs_shell_fat32_cd_cmd);
        (void)rs_shell_register("mv", "move/remove files", false, rs_shell_fat32_mv_cmd);
        (void)rs_shell_register("pwd", "print current directory", false, rs_shell_fat32_pwd_cmd);
        (void)rs_shell_register("mkdir", "make directories", false, rs_shell_fat32_mkdir_cmd);
        (void)rs_shell_register("rm", "remove files or directories", false, rs_shell_fat32_rm_cmd);
        (void)rs_shell_register("chmod", "change file mode bits", false, rs_shell_fat32_chmod_cmd);
        (void)rs_shell_register("touch", "change file timestamps", false, rs_shell_fat32_touch_cmd);
        (void)rs_shell_register("find", "search files in directory", false,
                                rs_shell_fat32_find_cmd);
        (void)rs_shell_register("file", "print file info", false, rs_shell_fat32_file_cmd);
        (void)rs_shell_register("write", "write string to file", false, rs_shell_fat32_write_cmd);
        (void)rs_shell_register("cat", "print file header", false, rs_shell_fat32_cat_cmd);
        (void)rs_shell_register("df", "report file system disk space usage", false,
                                rs_shell_fat32_df_cmd);
        (void)rs_shell_register("fatlabel", "set/get filesystem label or volume ID", false,
                                rs_shell_fat32_fatlabel_cmd);
        (void)rs_shell_register("image", "show image frames", false, rs_shell_app_image_cmd);
        (void)rs_shell_register("video", "video player", false, rs_shell_app_video_cmd);
        (void)rs_shell_register("audio", "audio player", false, rs_shell_app_audio_cmd);
        (void)rs_shell_register("lvgl", "show lvgl components", false, rs_shell_app_lvgl_cmd);
        (void)rs_shell_register("arduboy", "run arduboy", false, rs_shell_app_arduboy_cmd);
        (void)rs_shell_register("nes", "run nes simulator", false, rs_shell_app_nes_cmd);
        printf("register cmd num: %d\n", sh_cmd_len);
    }

    while (true) {
        printf("rs_shell > ");
        type_len = 0;

        do {
            type_ch = getchar();
            if ((type_ch >= 'a' && type_ch <= 'z') || (type_ch >= 'A' && type_ch <= 'Z') ||
                (type_ch >= '0' && type_ch <= '9') || type_ch == ' ' || type_ch == '.' ||
                type_ch == '/' || type_ch == '_' || type_ch == '"' || type_ch == '/' ||
                type_ch == '*' || type_ch == '-') {
                if ((type_len + 1U) >= sizeof(type_res)) {
                    continue;
                }
                putchar(type_ch);
                type_res[type_len++] = type_ch;
            } else if (type_ch == '\b' || type_ch == (char)127) {
                if (type_len == 0)
                    continue;
                printf("\b \b");
                type_res[type_len--] = 0;
            } else if (type_ch == (char)9) { // tab
                printf("tab\n");
                // rs_shell_search_cmd(type_res, type_len);
            }

        } while (type_ch != '\n' && type_ch != '\r');
        putchar('\n');

        type_res[type_len] = 0;
        if (sh_history_idx < RS_SHELL_MAX_HISTORY) {
            (void)rs_strlcpy(sh_history_table[sh_history_idx++], type_res,
                             sizeof(sh_history_table[0]));
        } else {
            for (uint8_t i = 1U; i < RS_SHELL_MAX_HISTORY; ++i) {
                (void)rs_strlcpy(sh_history_table[i - 1U], sh_history_table[i],
                                 sizeof(sh_history_table[0]));
            }
            (void)rs_strlcpy(sh_history_table[sh_history_idx - 1U], type_res,
                             sizeof(sh_history_table[0]));
        }

        rs_shell_parse_and_exec(type_res);
        // printf("ff_pwd: %s\n", fat32_pwd);
    }
}

void rs_shell_batch_run(void) {
    for (uint8_t i = 0U; i < sh_cmd_len; ++i) {
        if (sh_cmd_list[i].batch) {
            sh_cmd_list[i].handler(0, NULL);
        }
    }
}
