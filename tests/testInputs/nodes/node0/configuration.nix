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
  options.publicOnlyLegacyPkg = lib.mkOption {
    type = lib.types.str;
  };
  options.extraLegacyPkg = lib.mkOption {
    type = lib.types.str;
  };
  options.publicOnlyPkg = lib.mkOption {
    type = lib.types.str;
  };
  options.extraPkg = lib.mkOption {
    type = lib.types.str;
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
  options.folderOnlyPkg = lib.mkOption {
    type = lib.types.str;
  };
  options.folderOnlyModuleValue = lib.mkOption {
    type = lib.types.str;
  };

  config.pkg = inputs'.sample.packages.pkg;
  config.flakeOnlyPkg = inputs'.sample.packages.flakeOnlyPkg;
  config.legacyPkg = inputs'.sample.legacyPackages.legacyPkg;
  config.publicOnlyLegacyPkg = inputs'.sample.legacyPackages.publicOnlyLegacyPkg;
  config.extraLegacyPkg = inputs'.sample.legacyPackages.extraLegacyPkg;
  config.publicOnlyPkg = inputs'.sample.packages.publicOnlyPkg;
  config.extraPkg = inputs'.sample.packages.extra;
  config.folderOnlyPkg = inputs'.folderOnly.packages.pkg;
}
