#!/bin/python

import os

os.system('cd src/fatfs')
os.system('wget https://elm-chan.org/fsw/ff/arc/ff16.zip .')
os.system('unzip ff16.zip')
os.system('cp -rf ffconf.h diskio.c ff16/source/')

