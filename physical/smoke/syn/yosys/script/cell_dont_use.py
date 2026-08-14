#!/bin/python

import re

dff_dont_use_list = [
    '.*ED.*',
    '.*SD.*',
    '.*SED.* ',
    '.*SND.*',
    '.*DX.*',
    '.*D.*RSN.*',
    '.*LA.*RSN.*',
    '.*LAH.*',
    '.*LAL.*',
    '.*ND.*RSN.*',
]

comp_dont_use_list = [
    '.*DEL.*',
    '.*AO222.*',
    '.*AO33.*',
    '.*AOI222.*',
    '.*AOI33.*',
    '.*OA222.*',
    '.*OAI222.*',
    '.*OA33.*',
    '.*OAI33.*',
    '.*CLK.*',
    '.*CK.*',
    '.*NOR4.*',
    '.*V0.* ',
    '.*V24.* ',
    '.*V20.* ',
    '.*222.* ',
    '.*33.* ',
    '.*32.* ',
    '.*FDCAP.*',
    '.*PULL.*',
    '.*TBUF.*',
    '.*F_DIO.*',
    '.*IAO22.*',
    'LVT_MUX4HDV1',
]

res_dff_dont_use = []
res_comp_dont_use = []

with open('../../S110/scc011ums_hd_lvt_tt_v1p2_25c_basic.lib',
          'r',
          encoding='utf-8') as fp:
    for line in fp:
        for cell in dff_dont_use_list:
            val = re.match(r'.*cell\((' + cell + ')\)', line)
            if val:
                res_dff_dont_use.append(val.group(1))

        for cell in comp_dont_use_list:
            val = re.match(r'.*cell\((' + cell + ')\)', line)
            if val:
                res_comp_dont_use.append(val.group(1))

with open('dont_use_cell_dff', 'w', encoding='utf-8') as fp:
    for v in res_dff_dont_use:
        fp.write(f'"{v}" ')

with open('dont_use_cell_comb', 'w', encoding='utf-8') as fp:
    for v in res_comp_dont_use:
        fp.write(f'"{v}" ')
