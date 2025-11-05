#ifndef TINYSH_H__
#define TINYSH_H__

typedef void (*cmd_handler)(int argc, char **argv);

typedef struct {
    char *name;
    char *info;
    cmd_handler handler;
} tinysh_cmd_t;


#define MAX_CMD_ARGC 16
#define MAX_CMD_NUM 32
#define MAX_CMD_LEN 100
#define MAX_CMD_HIST 100

uint8_t tinysh_register(char *name, char *info, void *handler);
void tinysh_init();
void tinysh_launch();
#endif