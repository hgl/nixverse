{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
    in
    {
      load = import ./load.nix {
        inherit lib self;
      };
      lib = import ./lib.nix lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
    };
}
