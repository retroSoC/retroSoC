{
  description = "retroSoC lock-pinned open-source regression environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
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
          if [ ! -f "$root/config/dependencies.lock.json" ]; then
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
          ccache
          clangFormat14
          coreutils
          curl
          file
          findutils
          flex
          gawk
          gcc
          git
          gnugrep
          gnumake
          gnused
          gnutar
          gperftools
          launcher
          libunwind
          mold
          ncurses5
          numactl
          python3Full
          unzip
          which
          xz
          zlib
        ];
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
