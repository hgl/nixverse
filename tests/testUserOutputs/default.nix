{
  lib,
  lib',
  userFlake,
  ...
}:
let
  outputs = lib'.load {
    flake = userFlake;
    flakePath = userFlake.outPath;
  };
in
{
  outputs = {
    expr = {
      inherit (outputs) template legacyPackages;
    };
    expected = {
      template = 1;
      legacyPackages = {
        x86_64-linux = {
          foo = true;
          bar = true;
        };
      }
      // lib'.concatMapListToAttrs (
        system:
        lib.optionalAttrs (system != "x86_64-linux") {
          ${system} = {
            bar = true;
          };
        }
      ) lib.systems.flakeExposed;
    };
  };
}
