{
  lib,
  inputs',
  ...
}:
{
  imports = [
    inputs'.sample.modules.flakeOnlyModule
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
  options.flakeOnlyModuleValue = lib.mkOption {
    type = lib.types.str;
  };

  config.pkg = inputs'.sample.packages.pkg;
  config.flakeOnlyPkg = inputs'.sample.packages.flakeOnlyPkg;
  config.legacyPkg = inputs'.sample.legacyPackages.legacyPkg;
  config.hasPublicOnlyLegacyPkg = inputs'.sample.legacyPackages ? publicOnlyLegacyPkg;
  config.hasExtraLegacyPkg = inputs'.sample.legacyPackages ? extraLegacyPkg;
}
