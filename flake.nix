{
  description = "A semigraphical graphics library in Zig";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/x86_64-linux";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    zig.url = "github:silversquirl/zig-flake";
    zig.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs:
    let
      inherit (inputs.nixpkgs) lib;

      withPkgs =
        system:
        (import inputs.nixpkgs {
          inherit system;
          overlays = [ (_: _: { zig = inputs.zig.packages.${system}.nightly; }) ];
        });

      eachSystem = f: lib.genAttrs (import inputs.systems) (system: f (withPkgs system));

      treefmtEval = eachSystem (
        pkgs:
        inputs.treefmt-nix.lib.evalModule pkgs {
          programs.biome = {
            enable = true;
            settings = {
              formatter.indentStyle = "space";
              formatter.indentWidth = 2;
              linter.rules.complexity.useArrowFunction = "off";
              javascript.formatter.quoteStyle = "single";
            };
          };
          programs.deadnix.enable = true;
          programs.nixfmt.enable = true;
          programs.zig.enable = true;
        }
      );
    in
    {
      devShells = eachSystem (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = with pkgs; [
            bash
            vscode-langservers-extracted
            zig
            zig.zls
          ];
        };
      });

      checks = eachSystem (pkgs: {
        formatting = treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper;
      });

      formatter = eachSystem (pkgs: treefmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper);
    };
}
