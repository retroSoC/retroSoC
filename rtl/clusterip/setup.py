#!/bin/python

import os

ip = ['archinfo', 'common', 'i2c', 'pwm', 'ps2', 'rng', 'uart', 'spi', 'rtc', 'wdg', 'crc', 'timer']

for v in ip:
    # print(f'git clone git@github.com:retroSoC/{v}.git')
    os.system(f'git clone git@github.com:retroSoC/{v}.git')