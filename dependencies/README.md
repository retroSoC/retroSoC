# Locked Configuration Inputs

`dependencies.lock.json` is the source of truth for external repositories,
archives, OCI base images, Nix inputs, checksums, and CI tool bundles. Its digest
contributes to every build variant identity. `flake.lock` resolves the pinned Nix
inputs and is validated against this lock.

Publication inputs are also locked here: `publication_media`, the CeTZ, oxifmt,
wavy/jogs, bytefield, rivet, blockcell, circuiteria and tidy archives, and the
locally required Typst version in `publication_tools`. Package identities include
both name and version; CeTZ 0.3.4/0.5.2 and oxifmt 0.2.1/1.0.0 coexist as
separate cache entries. Library imports are checked as a complete offline closure.
They are prepared manually by `publications/build_datasheet.py setup`, without
adding a root Makefile target. See [Publications](../publications/README.md).

Do not add direct downloads to setup scripts or workflow YAML. Update the lock
with a full Git revision or verified SHA-256 checksum, validate it with:

```sh
python3 scripts/dependency_lock.py --lock dependencies/dependencies.lock.json
```

Then run the affected setup, doctor, test, and regression flow described in
[Engineering Workflow](../docs/engineering.md).

`sources.pdk_ics55_pll` locks OpenECOS `PLL_V02p1` at
`6ebb1a8f7f4ccbccdb7f587664fdfe63cd39e61b`. Restore only its seven integration
views with `python3 physical/pdk/setup.py --pdk ICS55 --component pll`, or as
part of normal ICS55 PDK setup (`--component all`, the default). The checkout
is `.cache/retrosoc/sources/ics55_ecos_pll`, outside replaceable Liberty caches.
Setup reports its revision and per-file SHA-256 values and refuses dirty or
unexpected checkouts under the usual update policy. The upstream license is
undetermined (`NOASSERTION`); Liberty lacks timing arcs and the macro has no
LOCK output. Acquisition neither selects the macro in a profile nor qualifies
PLL behavior, timing or release. Tiny platform integration remains pending.

The locked SKY130 OpenRAM SRAM archive is generated and published by the
`retroSoC/artifact` workflow. `physical/pdk/setup.py` verifies its SHA-256,
manifest, geometry, source revisions, generated-file hashes, and TT/SS views
before materializing it below `.cache/retrosoc/pdk/sky130/openram/`. Generated
Verilog, Liberty, LEF, GDS, and SPICE views are never committed here.

The HP profile locks the OpenC906 source (`sources.openc906`, Apache-2.0) below
`.cache/retrosoc/sources/openc906`; `make setup-openc906` installs it and
`make openc906-prepare` emits the build-variant `openc906.fl` filelist with the
reviewed hart-ID override substituted (the locked checkout is never modified).
OpenSBI, Linux stable, and Buildroot source revisions are locked for HP payload
builds. `make setup-hp-linux` installs the software sources below
`.cache/retrosoc/sources/`. VexiiRiscv remains locked as a Std-series asset: it
may be supplied through `VEXIIRISCV_ROOT`, its revision is still checked before
generated RTL is accepted, and `make std-vexii-generate` invokes the SBT
launcher for `GenerateRetroSocStd.scala`. Java 17 is a host runtime supplied
by Docker, Nix, or the documented Ubuntu prerequisites. No generated CPU RTL or
Linux build output belongs in Git.

`rtthread_hp` pins official RT-Thread v5.3.0 at
`99428a1e7f7447955aa860f7c969273a12095b8f`. `make setup-hp-rtthread` installs
that source, the checksum-locked `riscv_gnu_hp` RV64 compiler, and the hashed
SCons requirement in a local virtual environment. The BSP is copied into the
build variant and uses the upstream kernel/CPU port without modifying it.
The LP SDK retains its existing RV32 toolchain.

The libjpeg-turbo source archive is a host-verification input for the JPEG
accelerator. It supplies an implementation-independent interoperability oracle;
it is not linked into firmware or synthesized RTL. The repository-owned fixed
point model remains the bit-accurate source of expected RTL results.

The pinned libFLAC source and official FLAC test corpus are host-only APU-P5
verification inputs. Install them with `make setup-apu-reference`; neither is
linked into firmware, RTL, or the shipped APUMC bundle. Run
`make CONFIG=configs/ci/ihp130.mk apu-p5-corpus` to produce the checksum-pinned
per-file profile and independent PCM manifest.

The NPU Visual Wake Words archive is mirrored as an unmodified release asset in
`retroSoC/artifact`, with the original Silicon Labs URL retained as a fallback.
Both locations resolve to the same required SHA-256; setup accepts neither a
different archive nor a fallback with a non-HTTPS URL.

ECC is an explicit exception to the lock policy. `make ecc-setup` streams the
official `latest` installer with `--with-toolchain`; upstream manages versions,
archive checksums, installation directories and download caches. No ECC CLI or
private toolchain archive is pinned here. Shared PDK and tool dependencies used
by other flows remain locked. See [ECC setup](../physical/ecc/README.md).
