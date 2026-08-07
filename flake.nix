{
  description = "A semigraphical graphics library in Zig";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/x86_64-linux";
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

      formatter = eachSystem (pkgs: pkgs.nixfmt);
    };
}
