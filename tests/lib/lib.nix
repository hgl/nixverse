{
  lib,
  lib',
}:
{
  top = {
    lib = builtins.elem "x86_64-linux" lib.systems.flakeExposed;
    libP = {
      override = lib'.override;
    };
  };
  override = "top";
}
