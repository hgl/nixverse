{
  lib,
  lib',
  userFlake,
  ...
}:
let
  userLib = import ../../lib/load/userLib.nix {
    inherit lib lib' userFlake;
    userFlakePath = userFlake.outPath;
  };
in
{
  lib = {
    expr = userLib;
    expected = {
      args = {
        lib = true;
        libP.foo = "bar";
        inputs = [ "nixpkgs-unstable" ];
      };
      foo = "bar";
    };
  };
}
