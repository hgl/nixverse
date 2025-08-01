{
  lib,
  lib',
  self,
  userFlake,
  userFlakePath,
}:
pkgs:
let
  callPackage = pkgs.newScope {
    inherit pkgs' lib';
    nixverse = self.packages.${pkgs.stdenv.hostPlatform.system}.nixverse;
  };
  pkgs' = lib.mapAttrs (name: paths: callPackage (lib.last paths) { }) (
    lib'.allImportPathsInDirs [
      "${userFlakePath}/pkgs"
      "${userFlakePath}/private/pkgs"
    ]
  );
in
pkgs'
