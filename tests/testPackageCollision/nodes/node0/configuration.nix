{
  lib,
  pkgs',
  ...
}:
{
  options.pkg = lib.mkOption {
    type = lib.types.str;
  };

  config.pkg = pkgs'.pkg;
}
