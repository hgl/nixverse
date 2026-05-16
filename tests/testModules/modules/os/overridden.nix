{ lib, ... }:
{
  options.test.overridden = lib.mkOption {
    type = lib.types.str;
  };

  config.test.overridden = "os";
}
