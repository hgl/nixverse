{ lib, lib' }:
dirs: type:
let
  wrapModules =
    pathsByName:
    lib.mapAttrs (name: paths: {
      imports = paths;
    }) pathsByName;
  typePaths = lib'.allImportPathsInDirs (map (dir: "${dir}/${type}") dirs);
  osPaths = lib.optionalAttrs (lib.elem type [
    "nixos"
    "darwin"
  ]) (lib'.allImportPathsInDirs (map (dir: "${dir}/os") dirs));
in
wrapModules (osPaths // typePaths)
