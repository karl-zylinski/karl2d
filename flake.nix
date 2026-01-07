{
  description = "Karl2d flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      odin_updated = pkgs.odin.overrideAttrs (
        finalAttrs: previousAttrs: {
          version = "dev-2026-01";
          src = pkgs.fetchFromGitHub {
            owner = "odin-lang";
            repo = "Odin";
            rev = "393fec2f668ce2c1c7f2e885ab3e479d34e1e896";
            hash = "sha256-YvaEe69YSS/iQeCRyNQrslaY5ZgDW45y0rjb04eYpcw=";

          };
          patches = [ ];
        }
      );

      build_packages = with pkgs; [
        wayland
        wayland-scanner
        wayland-protocols
        gdb
        seer
        libGL
        valgrind
        libxkbcommon
        libschrift
        resvg
        odin_updated
        libx11
      ];
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = build_packages;
        shellHook = "zsh";
        name = "Karl2d dev shell";
      };
    };
}
