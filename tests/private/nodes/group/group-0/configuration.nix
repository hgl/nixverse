{ lib, nodes, ... }:
{
  options = {
    nixverse-test = lib.mkOption {
      type = lib.types.int;
    };
  };
  config = {
    nixpkgs.hostPlatform = "x86_64-linux";
    nixverse-test = nodes.current.final.x;
  };
}
