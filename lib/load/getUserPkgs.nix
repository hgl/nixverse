{
  lib,
  lib',
  self,
  userFlakePath,
}:
pkgs:
let
  callPackage = pkgs.newScope {
    inherit pkgs' lib';
    nixverse = self.packages.${pkgs.stdenv.hostPlatform.system}.nixverse;
  };
  pkgs' = lib.mapAttrs (name: paths: callPackage (lib.head paths) { }) (
    lib'.allImportPathsInDirs [
      "${userFlakePath}/private/pkgs"
      "${userFlakePath}/pkgs"
    ]
  );
in
pkgs'
