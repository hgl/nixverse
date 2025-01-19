{ lib, ... }:
{
  options = {
    nixverse-test = lib.mkOption {
      type = lib.types.str;
    };
  };
  config = {
    nixpkgs.hostPlatform = "x86_64-linux";
    nixverse-test = "bar";
  };
}
