{
  lib,
  inputs',
  ...
}:
{
  imports = [
    inputs'.sample.modules.inputModule
    inputs'.sample.modules.flakeOnlyModule
    inputs'.sample.modules.publicOnlyModule
    inputs'.sample.modules.privateModule
    inputs'.folderOnly.modules.folderOnlyModule
    inputs'.folderOnly.modules.folderOsModule
    inputs'.folderOnly.modules.folderOverrideModule
  ];

  options.pkg = lib.mkOption {
    type = lib.types.str;
  };
  options.flakeOnlyPkg = lib.mkOption {
    type = lib.types.str;
  };
  options.legacyPkg = lib.mkOption {
    type = lib.types.str;
  };
  options.hasPublicOnlyLegacyPkg = lib.mkOption {
    type = lib.types.bool;
  };
  options.hasExtraLegacyPkg = lib.mkOption {
    type = lib.types.bool;
  };
  options.inputModuleValue = lib.mkOption {
    type = lib.types.str;
  };
  options.flakeOnlyModuleValue = lib.mkOption {
    type = lib.types.str;
  };
  options.publicOnlyModuleValue = lib.mkOption {
    type = lib.types.str;
  };
  options.privateModuleValue = lib.mkOption {
    type = lib.types.str;
  };
  options.folderOnlyHasPkg = lib.mkOption {
    type = lib.types.bool;
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

  config.pkg = inputs'.sample.packages.pkg;
  config.flakeOnlyPkg = inputs'.sample.packages.flakeOnlyPkg;
  config.legacyPkg = inputs'.sample.legacyPackages.legacyPkg;
  config.hasPublicOnlyLegacyPkg = inputs'.sample.legacyPackages ? publicOnlyLegacyPkg;
  config.hasExtraLegacyPkg = inputs'.sample.legacyPackages ? extraLegacyPkg;
  config.folderOnlyHasPkg = inputs'.folderOnly.packages ? pkg;
}
