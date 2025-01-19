{
  lib,
  inputs,
  lib',
}:
{
  common = {
    lib = builtins.elem "x86_64-linux" lib.systems.flakeExposed;
    inputs = inputs.nixpkgsLib.lib.global;
    libP = {
      inherit (lib') top;
      override = lib'.override;
    };
  };
  override = "common";
}
