#include <firmware.h>
#include <tinyprint.h>
#include <tinyprintf.h>
#include <tinystring.h>
#include <tinysh.h>

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

static void tinysh_find_cmd(char *cmd) {
    bool is_find = false;
    for(uint8_t i = 0; i < sh_cmd_len; ++i) {
        if(strcmp(cmd, sh_cmd_list[i].name) == 0) {
            is_find = true;
            sh_cmd_list[i].handler();
            break;
        }
    }

    if(!is_find) printf("recv cmd: %s not found\n", cmd);
}

static void tinysh_help() {
    for(uint8_t i = 0; i < sh_cmd_len; ++i) {
        printf("cmd: %8s info: %16s\n", sh_cmd_list[i].name, sh_cmd_list[i].info);
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
}

void tinysh_launch() {
    char type_res[MAX_CMD_LEN], type_ch;
    uint8_t type_len;

    tinysh_welcome();
    // register internal cmd
    tinysh_register("help", "default help info", tinysh_help);
    tinysh_register("history", "print history list", tinysh_history_list);
    // ls -> fatfs
    //
    while(1) {
        printf("tinysh > ");
        type_len = 0;

        do {
            type_ch = getchar();
            if((type_ch >= 'a' && type_ch <= 'z') || (type_ch >= 'A' && type_ch <= 'Z') || (type_ch >= '0' && type_ch <= '9')) {
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

        tinysh_find_cmd(type_res);
    }
}
