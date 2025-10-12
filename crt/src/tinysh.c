#include <firmware.h>
#include <tinyprint.h>
#include <tinyprintf.h>
#include <tinystring.h>
#include <tinysh.h>

static tinysh_cmd_t sh_cmd_list[MAX_CMD_NUM];
static uint8_t sh_cmd_len;

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
        printf("cmd: %s info: %s\n", sh_cmd_list[i].name, sh_cmd_list[i].info);
    }
}

void tinysh_init() {
    sh_cmd_len = 0;
}

void tinysh() {
    char type_res[MAX_CMD_LEN], type_ch;
    uint8_t type_len;
    // register internal cmd
    tinysh_register("help", "default help info", tinysh_help);
    while(1) {
        printf("tinysh> ");
        type_len = 0;

        do {
            type_ch = getchar();
            if((type_ch >= 'a' && type_ch <= 'z') || (type_ch >= 'A' && type_ch <= 'Z') || (type_ch >= '0' && type_ch <= '9')) {
                if(type_len == MAX_CMD_LEN) break;
                putchar(type_ch);
                type_res[type_len++] = type_ch;
            } else if(type_ch == 'h'){
                if(type_len == 0) continue;
                // type_res[type_len--];
            }

        } while(type_ch != '\n' && type_ch != '\r');
        putchar('\n');
        
        type_res[type_len] = 0;
        tinysh_find_cmd(type_res);
    }
}
