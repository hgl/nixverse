{
  lib,
  lib',
  self,
}:
flake:
{ nixpkgs, system }:
let
  inherit (lib'.internal) importDirAttrs;
  publicDir = flake.outPath;
  privateDir = "${publicDir}/private";
  rawPkgs = importDirAttrs "${publicDir}/pkgs" // importDirAttrs "${privateDir}/pkgs";
  pkgs = nixpkgs.legacyPackages.${system};
  callPackage = pkgs.newScope {
    inherit pkgs';
  };
  pkgs' =
    lib.removeAttrs self.packages.${system} [ "default" ]
    // lib.mapAttrs (_: v: callPackage v { }) rawPkgs;
in
pkgs'
