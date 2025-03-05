{
  lib,
  lib',
  self,
}:
flake: outputs:
let
  final = import ./load.nix {
    inherit
      lib
      lib'
      self
      flake
      outputs
      ;
  };
in
lib.recursiveUpdate {
  inherit (final)
    nixosModules
    darwinModules
    homeManagerModules
    nixosConfigurations
    darwinConfigurations
    ;
  packages = lib'.forAllSystems (
    system:
    let
      pkgs = flake.inputs.nixpkgs-unstable.legacyPackages.${system};
    in
    lib.mapAttrs (_: v: pkgs.callPackage v { }) final.pkgs
  );
} outputs
// {
  inherit (final) nixverse;
}
