# ECC Setup and ICS55 Core Hardening

`make ecc-setup` installs the latest official ECOS Chip Compiler release and its
required toolchain by directly executing:

```sh
curl -fsSL http://release.openecos.com/installers/ecc/latest/ecc-installer.sh | sh -s -- --with-toolchain
```

The setup helper uses Bash with `pipefail` so a failed download or installer
returns failure. It does not save the installer script or pin ECC versions in
the repository dependency lock. The upstream installer selects versions,
checks payload checksums, and installs ECC, OSS CAD Suite, ECC Sizer and the
ICS55 PDK. Every explicit setup invocation follows `latest`; the installer
manages reuse of same-version downloads and installations.

Run from the repository root, without a SoC profile:

```sh
make ecc-setup
"${XDG_BIN_HOME:-$HOME/.local/bin}/ecc" --version
"${XDG_BIN_HOME:-$HOME/.local/bin}/ecc" version --json
export PATH="${XDG_BIN_HOME:-$HOME/.local/bin}:$PATH"
```

The official installer currently requires Linux x86_64 with glibc >= 2.34,
curl, GNU tar, gzip, bzip2 and sha256sum; the repository entrypoint also needs
Bash and Python 3. Setup verifies the resulting executable wrapper and its
version/runtime JSON before reporting success.

No install-directory environment variables are overridden. With upstream
defaults, the wrapper is `~/.local/bin/ecc`, versioned ECC/tools/PDKs live in
`~/.local/share/ecc/`, downloads in `~/.cache/ecc/downloads/`, and the receipt
in `~/.config/ecc/ecc-receipt.json`. Existing `ECC_INSTALL_DIR` and XDG variables
are handled by the official script. The wrapper selects the installed private
toolchain. Setup prints PATH guidance without changing shell startup files or
creating a repository activation script. Old clones and caches are not removed.

## Existing physical adapter

The physical adapter targets the padless `retrosoc_core` macro on the committed
`configs/ci/ics55.mk` profile. It retains its independent locked PDK inputs,
H7CR slow Liberty view, source export and multi-clock constraints. Installing
the upstream private PDK does not replace those shared inputs.

Physical targets use the already installed wrapper, defaulting to
`${XDG_BIN_HOME:-$HOME/.local/bin}/ecc`; override `ECC_BIN` to select another
installation. They do not implicitly install or update ECC. Doctor records
the actual CLI version and checks the project rather than requiring alpha.10.

The existing `harden` configuration and current profile still require
compatibility qualification with the installed release. Installing ECC alone
does not establish that `ecc-doctor`, `ecc-core`, or `ecc-package` will pass.
This setup change does not migrate or validate synthesis, STA, place-and-route,
or Tiny/ICS55 support. The profile, clock, padless-cell and project checks remain
in place and report actual incompatibilities.

Physical outputs remain below `build/<variant>/physical/ecc/core/`. This
experimental adapter does not establish foundry DRC/LVS, IR/EM, ESD, package,
board or production-signoff closure.
