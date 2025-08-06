{
  lib,
  lib',
  userFlakePath,
}:
{
  nixos =
    lib.mapAttrs
      (name: paths: {
        imports = paths;
      })
      (
        lib'.allImportPathsInDirs [
          # "${userFlakePath}/modules/common"
          # "${userFlakePath}/private/modules/common"
          "${userFlakePath}/modules/nixos"
          "${userFlakePath}/private/modules/nixos"
        ]
      );
  darwin =
    lib.mapAttrs
      (name: paths: {
        imports = paths;
      })
      (
        lib'.allImportPathsInDirs [
          # "${userFlakePath}/modules/common"
          # "${userFlakePath}/private/modules/common"
          "${userFlakePath}/modules/darwin"
          "${userFlakePath}/private/modules/darwin"
        ]
      );
  home =
    lib.mapAttrs
      (name: paths: {
        imports = paths;
      })
      (
        lib'.allImportPathsInDirs [
          "${userFlakePath}/modules/home"
          "${userFlakePath}/private/modules/home"
        ]
      );
  flake =
    lib.mapAttrs
      (name: paths: {
        imports = paths;
      })
      (
        lib'.allImportPathsInDirs [
          "${userFlakePath}/modules/flake"
          "${userFlakePath}/private/modules/flake"
        ]
      );
}
