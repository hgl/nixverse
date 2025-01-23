{ lib, nodes, ... }:
{
  options = {
    nixverse-test = lib.mkOption {
      type = lib.types.attrs;
    };
  };
  config.nixverse-test = {
    bar = nodes.current.x;
  };
}
