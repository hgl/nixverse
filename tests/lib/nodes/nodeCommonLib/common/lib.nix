{
  lib,
  lib',
}:
{
  common = {
    lib = builtins.elem "x86_64-linux" lib.systems.flakeExposed;
    libP = {
      inherit (lib') top;
      override = lib'.override;
    };
  };
  override = "common";
}
