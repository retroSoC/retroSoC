# Development Environment

## Scope

The Docker image, Nix application, and manual bootstrap expose one Linux x86_64
open-source development environment. It includes the locked Ubuntu 22.04 tool
bundles for Verilator, Verible, sv2v, Icarus Verilog, Yosys, SymbiYosys,
Bitwuzla, OpenSTA, OpenOCD, and the RISC-V GNU toolchain. The GNU bundle
includes `riscv32-unknown-elf-gdb`, which is used with OpenOCD by the Hazard3
remote-bitbang debug acceptance flow. It also installs the locked Python build
and quality dependencies, clang-format-14, GNU Make, C/C++ build tools, and
runtime libraries required by those binaries.

The environment intentionally does not include PDK repositories, managed RTL,
application archives, build output, or compiler caches. These inputs are
specific to a checkout and continue to be installed by make setup or
make setup-regression. The latter prepares the four pull-request PDK profiles
in a fixed order.

The optional Xezim and CVC simulation backends are also outside the locked
environment. They must be installed separately and selected through explicit
`XEZIM` and `CVC` executable paths. They are local compatibility tools, not
reproducible CI inputs.

## Shared Bootstrap

scripts/development_environment.py is the only tool installer for the three
entry points. It reads dependencies/dependencies.lock.json, verifies every tool
archive checksum, creates a virtual environment, installs the hash-pinned
Python requirements, and writes:

- .cache/retrosoc/development/development-environment.json: installed input
  versions and requirement digests.
- .cache/retrosoc/development/activate.sh: the reproducible PATH and virtual
  environment activation script.

Bootstrap is idempotent. It reinstalls tools or Python packages when the
dependency lock, selected tool set, or Python requirement hashes change.

~~~sh
python3 scripts/development_environment.py bootstrap
source .cache/retrosoc/development/activate.sh
python3 scripts/development_environment.py check
~~~

The default cache is inside the checkout. Set RETROSOC_DEVELOPMENT_CACHE to
use a shared cache; users sharing that cache must use the same repository
revision and lock file.

## Docker

docker/Dockerfile pins its Ubuntu 22.04 base image by OCI digest. The digest
is recorded as a container_images entry in dependencies/dependencies.lock.json.
Build it from the repository root so the Docker build receives the exact lock,
bootstrap scripts, and requirement files.

~~~sh
docker build --tag retrosoc-dev --file docker/Dockerfile .
docker run --rm --init --platform linux/amd64 --user "$(id -u):$(id -g)" -it \
  -v "$PWD:/workspace/retrosoc" retrosoc-dev bash
~~~

The mounted checkout receives PDKs, managed sources, caches, and build output.
The explicit user mapping prevents Docker from creating root-owned checkout files.
The image itself has no mutable project state. Docker on Apple Silicon must use
linux/amd64 emulation and is therefore expected to run the EDA tools more slowly.

## Nix

flake.nix exposes nix run .#dev. It is only supported on Linux x86_64 because
the locked tool bundles are Ubuntu x86_64 binaries. Its buildFHSEnv layer
provides the Ubuntu-compatible runtime libraries, then calls the shared
bootstrap script in the current checkout.

~~~sh
nix run .#dev
nix run .#dev -- make CONFIG=configs/ci/ihp130.mk SIMU=IVERILOG sim
~~~

flake.lock pins nixpkgs. scripts/dependency_lock.py compares its resolved
revision and NAR hash with dependencies/dependencies.lock.json, so a Nix input update
requires an explicit lock review.

## Validation

Run the environment check before using a manually shared cache. Build the
Docker image after Dockerfile or bootstrap changes. On a Linux x86_64 host,
run nix flake check and a short nix run .#dev command after flake changes. Then
run make setup-regression and the regression tier appropriate for the change.
