{ lib, ... }:
{
  options.test.osOnly = lib.mkOption {
    type = lib.types.str;
  };

  config.test.osOnly = "os";
}
