{ lib, node, ... }:
{
  options = {
    nixverse-test = lib.mkOption {
      type = lib.types.attrs;
    };
  };
  config.nixverse-test = {
    bar = node.x;
  };
}
