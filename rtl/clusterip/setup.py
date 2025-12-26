#!/bin/python

import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

ip = ['archinfo', 'clint', 'common', 'crc', 'gpio', 'i2c', 'i2s', 'plic', 'ps2', 'pwm', 'rng', 'rtc', 'spi', 'timer', 'uart', 'wdg']

for v in ip:
    # print(f'git clone git@github.com:retroSoC/{v}.git')
    os.system(f'git clone https://github.com/retroSoC/{v}.git {SCRIPT_DIR}/{v}')