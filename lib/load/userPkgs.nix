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
    inherit pkgs';
    nixverse = self.packages.${pkgs.stdenv.hostPlatform.system}.nixverse;
  };
  pkgs' = lib.mapAttrs (name: paths: callPackage (lib.last paths) { }) (
    lib'.allDirEntryImportPaths [
      "${userFlakePath}/pkgs"
      "${userFlakePath}/private/pkgs"
    ]
  );
in
pkgs'
