{
  lib,
  lib',
  nixpkgs,
}:
flake:
let
  final = import ./load.nix {
    inherit
      lib
      lib'
      nixpkgs
      flake
      ;
  };
in
{
  inherit (final)
    nixosModules
    darwinModules
    homeManagerModules
    nixosConfigurations
    darwinConfigurations
    nixverse
    ;
  packages = lib'.forAllSystems (
    system:
    let
      pkgs = flake.inputs.nixpkgs-unstable.legacyPackages.${system};
    in
    lib.mapAttrs (_: v: pkgs.callPackage v { }) final.pkgs
  );
}
