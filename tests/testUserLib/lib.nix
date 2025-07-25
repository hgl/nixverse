{
  lib,
  lib',
  inputs,
}:
{
  args = {
    lib = builtins.elem "x86_64-linux" lib.systems.flakeExposed;
    libP = {
      foo = lib'.foo;
    };
    inputs = lib.attrNames inputs;
  };
  foo = "bar";
}
