{ lib, inputs', ... }:
{
  options.pkg = lib.mkOption {
    type = lib.types.str;
  };

  config.pkg = inputs'.sample.packages.pkg;
}
