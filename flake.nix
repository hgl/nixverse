{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
    in
    {
      load = import ./load.nix {
        inherit lib self;
        lib' = self.lib;
      };
      lib = import ./lib.nix {
        inherit lib;
        lib' = self.lib;
      };
    };
}
