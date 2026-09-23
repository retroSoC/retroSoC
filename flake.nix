{
  description = "retroSoC lock-pinned open-source regression environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      ncursesTermlib = pkgs.ncurses.override { withTermlib = true; };
      runtimeLibraryPath = pkgs.lib.makeLibraryPath [
        ncursesTermlib
        pkgs.bzip2.out
      ];
      clangFormat14 = pkgs.writeShellApplication {
        name = "clang-format-14";
        runtimeInputs = [ pkgs.clang_14 ];
        text = "exec clang-format \"$@\"";
      };
      launcher = pkgs.writeShellApplication {
        name = "retrosoc-dev";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          root="$PWD"
          if [ ! -f "$root/dependencies/dependencies.lock.json" ]; then
            echo "retrosoc-dev: run this command from a retroSoC checkout" >&2
            exit 2
          fi

          cache="''${RETROSOC_DEVELOPMENT_CACHE:-}"
          if [ -z "$cache" ]; then
            cache="$root/.cache/retrosoc/development"
          fi
          python3 "$root/scripts/development_environment.py" \
            --root "$root" \
            --cache "$cache" \
            bootstrap
          # shellcheck source=/dev/null
          source "$cache/activate.sh"
          if [ "$#" -eq 0 ]; then
            exec bash
          fi
          exec "$@"
        '';
      };
      developmentShell = pkgs.buildFHSEnv {
        name = "retrosoc-development";
        targetPkgs = pkgs: with pkgs; [
          bash
          binutils
          bzip2
          bzip2.out
          ccache
          clangFormat14
          coreutils
          curl
          expat
          file
          findutils
          flex
          gawk
          gcc
          gmp
          git
          gnugrep
          gnumake
          gnused
          gnutar
          gperftools
          isl
          launcher
          libunwind
          libmpc
          mold
          mpfr
          ncursesTermlib
          numactl
          jdk17_headless
          perl
          python310Full
          readline
          tcl
          unzip
          which
          xz
          zlib
          zlib.dev
          zstd
        ];
        profile = ''
          export LD_LIBRARY_PATH="${runtimeLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        '';
        runScript = "retrosoc-dev";
      };
      developmentApplication = pkgs.writeShellApplication {
        name = "retrosoc-dev";
        text = ''
          exec ${developmentShell}/bin/retrosoc-development retrosoc-dev "$@"
        '';
      };
    in
    {
      packages.${system}.dev = developmentShell;
      apps.${system}.dev = {
        type = "app";
        program = "${developmentApplication}/bin/retrosoc-dev";
      };
    };
}
