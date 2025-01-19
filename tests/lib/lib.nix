{
  lib,
  inputs,
  lib',
}:
{
  top = {
    lib = builtins.elem "x86_64-linux" lib.systems.flakeExposed;
    inputs = inputs.nixpkgsLib.lib.global;
    libP = {
      override = lib'.override;
    };
  };
  override = "top";
}
