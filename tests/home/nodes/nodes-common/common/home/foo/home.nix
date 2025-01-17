{ lib, node, ... }:
{
  options = {
    nixverse-test = lib.mkOption {
      type = lib.types.str;
    };
  };
  config.nixverse-test = node.x;
}
