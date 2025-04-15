#!/bin/bash
set -ex
if test ! -s osu018_stdcells.lib; then
	wget --continue -O osu018_stdcells.lib.part http://vlsiarch.ecen.okstate.edu/flows/MOSIS_SCMOS/`
			`latest/cadence/lib/tsmc018/signalstorm/osu018_stdcells.lib
	mv osu018_stdcells.lib.part osu018_stdcells.lib
fi
