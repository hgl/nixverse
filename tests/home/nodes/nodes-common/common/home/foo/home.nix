{ lib, nodes, ... }:
{
  options = {
    nixverse-test = lib.mkOption {
      type = lib.types.str;
    };
  };
  config.nixverse-test = nodes.current.x;
}
