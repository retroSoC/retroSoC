#!/bin/python

import os

# Always use the script directory as the base to avoid failures in different working directories
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
APP_DIR = SCRIPT_DIR
FATFS_DIR = os.path.join(APP_DIR, 'fatfs')
COREMARK_DIR = os.path.join(APP_DIR, 'coremark')
LVGL_DIR = os.path.join(APP_DIR, 'lvgl')
LVGL_NAME = 'v9.4.0.tar.gz'

# print(APP_DIR)
# print(FATFS_DIR)
# print(COREMARK_DIR)


def prepend_line(filename, line):
    with open(filename, 'r') as f:
        content = f.read()
    with open(filename, 'w') as f:
        f.write(line + '\n' + content)

def replace_line(filename, old, new):
    lines = ''
    with open(filename, 'r', encoding='utf-8') as fp:
        for v in fp:
            if old in v:
                lines += v.replace(old, new)
            else:
                lines += v

    with open(filename, 'w', encoding='utf-8') as fp:
        fp.writelines(lines)


os.system(f'mkdir -p "{FATFS_DIR}"/ff16 && cd "{FATFS_DIR}"/ff16 && if [ -d source ]; then echo "[fatfs] already exists, skip"; else wget https://elm-chan.org/fsw/ff/arc/ff16.zip && unzip -q ff16.zip && echo "[fatfs] downloaded and extracted"; fi')
os.system(f'cd "{FATFS_DIR}" && cp -rf ffconf.h diskio.c ff16/source/')

os.system(f'git clone https://github.com/eembc/coremark.git {COREMARK_DIR}/coremark-main')
os.system(f'cd {COREMARK_DIR}/coremark-main && git checkout 1f483d5b8316753a742cbf5590caf5bd0a4e4777')
os.chdir(f'{COREMARK_DIR}/coremark-main')
prepend_line('coremark.h', '#include <tinyprintf.h>')
replace_line('core_main.c', 'main', 'core_main')


# os.system(f'cd "{LVGL_DIR}" && if ls -1d lvgl-* >/dev/null 2>&1; then echo "[lvgl] already exists, skip"; else wget https://github.com/lvgl/lvgl/archive/refs/tags/{LVGL_NAME} && tar -xf {LVGL_NAME} && echo "[lvgl] downloaded and extracted"; fi')