{
  lib,
  lib',
  userFlake,
  userFlakePath,
}:
pkgs:
lib.mapAttrs (name: paths: pkgs.callPackage (lib.last paths) { }) (
  lib'.allDirEntryImportPaths [
    "${userFlakePath}/pkgs"
    "${userFlakePath}/private/pkgs"
  ]
)
