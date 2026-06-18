{
  lib,
  inputs',
  modules',
  pkgs',
  ...
}:
{
  imports = [
    modules'.bundleModule
    modules'.publicOnlyModule
    modules'.privateModule
    modules'.folderOnlyModule
    modules'.folderOsModule
    modules'.folderOverrideModule
  ];

  options.bundlePkgInPkgs = lib.mkOption {
    type = lib.types.str;
  };
  options.publicOnlyPkgInPkgs = lib.mkOption {
    type = lib.types.str;
  };
  options.extraPkgInPkgs = lib.mkOption {
    type = lib.types.str;
  };
  options.bundleModuleValue = lib.mkOption {
    type = lib.types.str;
  };
  options.publicOnlyModuleValue = lib.mkOption {
    type = lib.types.str;
  };
  options.privateModuleValue = lib.mkOption {
    type = lib.types.str;
  };
  options.hasBundleInput = lib.mkOption {
    type = lib.types.bool;
  };
  options.folderOnlyPkgInPkgs = lib.mkOption {
    type = lib.types.str;
  };
  options.folderOnlyModuleValue = lib.mkOption {
    type = lib.types.str;
  };
  options.folderOsModuleValue = lib.mkOption {
    type = lib.types.str;
  };
  options.folderOverrideModuleValue = lib.mkOption {
    type = lib.types.str;
  };

  config.bundlePkgInPkgs = pkgs'.pkg;
  config.publicOnlyPkgInPkgs = pkgs'.publicOnlyPkg;
  config.extraPkgInPkgs = pkgs'.extra;
  config.hasBundleInput = inputs' ? sample || inputs' ? folderOnly;
  config.folderOnlyPkgInPkgs = pkgs'.folderOnlyPkg;
}
