#!/bin/python

import os

cur_path = os.getcwd()
lvgl_name = 'v9.4.0.tar.gz'

os.system('cd src/fatfs')
os.system('wget https://elm-chan.org/fsw/ff/arc/ff16.zip .')
os.system('unzip ff16.zip')
os.system('cp -rf ffconf.h diskio.c ff16/source/')
os.system(f'cd {cur_path}')

os.system('cd src/lvgl')
os.system(f'wget https://github.com/lvgl/lvgl/archive/refs/tags/{lvgl_name}')
os.system(f'tar -xvf {lvgl_name}')
# os.system('cp -rf ffconf.h diskio.c ff16/source/')