#import "../style.typ": *
#change-start("v05-emphasis-development-environment","Selected body emphasis: development environment")

=== Development environment and reproducible inputs
#change-start("v05-refresh-development","Supported development environment and evidence stages")
#let environment=data.system_reference.development_environment
The supported open-source tool environment targets #environment.platform. The Docker image,
Nix application and manual Ubuntu #environment.ubuntu bootstrap share the repository's locked
installer. Docker and Nix use Python #environment.python to match the pinned requirement sets;
both provide Java #environment.java for the locked SBT #environment.sbt toolchain. These are
development prerequisites, *not additional SoC functions* or a statement of target performance.

#ds-table("development-entrypoints",[Development entrypoints and their boundaries],
  ([Entrypoint],[Reproducible input],[Use and evidence boundary]),
  (([Docker],[Digest-pinned Ubuntu base and the shared dependency lock.],[The image supplies tools. A mounted checkout supplies managed RTL, PDKs, application inputs and generated outputs.]),
   ([Nix],[Locked nixpkgs and a *Linux x86_64* FHS environment.],[The launcher uses the same bootstrap in the current checkout. A successful flake check does not establish runtime regression success.]),
   ([Manual Ubuntu],[Shared bootstrap, archive checksums and pinned Python requirements.],[Activate and check the installed environment, then prepare the selected profile's dependencies before building.])),
  widths:(0.65fr,1.45fr,2.15fr))

The environment does not package PDK repositories, managed RTL, application archives,
build products or compiler caches. Follow the engineering guide's setup and doctor flows
for the selected checkout and profile. Preserve the installed environment manifest and
input hashes with each result; the full setup commands belong in that guide.

Record installation, environment checking and runtime regression as separate stages.
The hosted development-environment workflow currently runs the IHP130 behavioral-only
regression; it does not add synthesis, netlist, STA or silicon evidence. A failed runtime
stage remains a failure even when Docker build or Nix installation/checking succeeds.
See @release-verification for the commit-bound observation and its UTC sampling time.
#source-note("docs/development-environment.md",title:"Supported environment, setup commands and activation")
#source-note("dependencies/dependencies.lock.json",title:"Locked sources, tools, containers and Nix inputs")
#source-note(".github/workflows/development-environment.yml",title:"Actual installation and behavioral runtime stages")
#change-end("v05-refresh-development")

#change-end("v05-emphasis-development-environment")
