{
  lib,
  lib',
}:
flake: outputs:
let
  final = import ./load.nix {
    inherit lib lib' flake;
  };
in
assert lib.assertMsg (!(outputs ? nixverse)) "Do not specify flake output \"nixverse\".";
lib.recursiveUpdate {
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
} outputs
