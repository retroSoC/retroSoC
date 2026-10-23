# Device Simulation Models

This directory contains committed device models used only by retroSoC simulation.
The models are excluded from the self-owned synthesizable RTL style profile and
retain their upstream notices and behavior. The repository import normalizes
line endings and trailing whitespace.

`ESP_PSRAM64H.sv` is the project-owned SDR SPI/QPI 8 MiB reference model,
shared by Mini's separate PSRAM controller and Tiny's XPI NSS1 verification.
It was relocated from `rtl/mini/dv/model` for TINY-R2-P8; controller/product
acceptance evidence is not interchangeable. Keep its existing fault-injection
and timing parameters compatible with Mini.

| File | Upstream source | Revision | Upstream SHA-256 |
| --- | --- | --- | --- |
| `at24cxxx.sv` | `https://github.com/retroSoC/i2c.git` | `73b024547c5cd70fb8bf801cc7757db2536c604f` | `636ed7e58574735a80943122178da8e1b23a48d443ec11d96ccdbd8618da404b` |
| `mic.sv` | `https://github.com/retroSoC/i2s.git` | `bd0978e8b45e4cf4c1335a1fa7311385d2a4e805` | `2d5264092bac13f28c5e38cfba4a9288afb6d704c7821f40265177c32715a6b3` |
| `w25q128jvxim.sv` | `https://github.com/retroSoC/spi.git` | `515cb408806584525605b4747db5e890dbdf1928` | `4b95f007a39854dc2690cf0b608b1b4b56a61adbf1e7c736e7ab5d44d46a112f` |
| `ESP_PSRAM64H.sv` | retroSoC retained Mini model, moved for Tiny R2-P8 shared verification | repository history | source-bound in the Tiny P8 snapshot |

The Winbond model retains its upstream copyright and "All Rights Reserved"
notice. Inclusion here records provenance and does not relicense that model
under the retroSoC project license.
