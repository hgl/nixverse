{ lib, ... }:
{
  options.foo = lib.mkOption {
    type = lib.types.attrsOf lib.types.int;
  };
  config = {
    nixpkgs.hostPlatform = "x86_64-linux";
    foo = {
      group0 = 1;
    };
  };
}
