# RIB and Experimental IP

This directory owns project RTL IP.

rib groups maintained blocks by function: interconnect, util, memory,
storage, serial, multimedia, and peripheral. The Mini SoC selects active
sources explicitly in rtl/mini/filelist/ip.fl, whose source order is part of
the build contract.

experimental contains retained inactive RTL. It is not included by any active
filelist and must not become a build dependency without an explicit integration
change and matching validation.
