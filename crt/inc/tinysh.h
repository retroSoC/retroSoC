#ifndef TINYSH_H__
#define TINYSH_H__

typedef void (*cmd_handler)(void);

typedef struct {
    char *name;
    char *info;
    cmd_handler handler;
} tinysh_cmd_t;


#define MAX_CMD_NUM 32
#define MAX_CMD_LEN 36

uint8_t tinysh_register(char *name, char *info, void *handler);
void tinysh_init();
void tinysh_launch();
#endif