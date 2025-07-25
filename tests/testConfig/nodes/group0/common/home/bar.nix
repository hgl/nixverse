{ lib, ... }:
{
  options.baz = lib.mkOption {
    type = lib.types.attrsOf lib.types.int;
  };
  config = {
    baz = {
      group0 = 1;
    };
  };
}
