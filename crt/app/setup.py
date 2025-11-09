#!/bin/python

import os

# 始终以脚本所在目录为基准，避免在不同工作目录下失败
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
APP_DIR = SCRIPT_DIR
SRC_DIR = os.path.join(APP_DIR, 'src')
FATFS_DIR = os.path.join(SRC_DIR, 'fatfs')
LVGL_DIR = os.path.join(SRC_DIR, 'lvgl')

lvgl_name = 'v9.4.0.tar.gz'

os.system(f'mkdir -p "{FATFS_DIR}"/ff16 && cd "{FATFS_DIR}"/ff16 && if [ -d source ]; then echo "[fatfs] 已存在，跳过"; else wget https://elm-chan.org/fsw/ff/arc/ff16.zip && unzip -q ff16.zip && echo "[fatfs] 下载并解压成功"; fi')
os.system(f'cd "{FATFS_DIR}" && cp -rf ffconf.h diskio.c ff16/source/')

os.system(f'cd "{LVGL_DIR}" && if ls -1d lvgl-* >/dev/null 2>&1; then echo "[lvgl] 已存在，跳过"; else wget https://github.com/lvgl/lvgl/archive/refs/tags/{lvgl_name} && tar -xf {lvgl_name} && echo "[lvgl] 下载并解压成功"; fi')