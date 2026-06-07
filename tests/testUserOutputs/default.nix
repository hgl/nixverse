{
  lib,
  lib',
  userFlake,
  ...
}:
let
  outputs = lib'.load {
    inputs = userFlake.inputs // {
      self = userFlake;
    };
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
          nodePkgs = true;
          nodePkgs' = "foo-x86_64-linux";
          nodeLib = true;
          nodeLib' = true;
          bar = true;
          perSystemPkgs' = "foo-x86_64-linux";
        };
      }
      // lib'.concatMapListToAttrs (
        system:
        lib.optionalAttrs (system != "x86_64-linux") {
          ${system} = {
            bar = true;
            perSystemPkgs' = "foo-${system}";
          };
        }
      ) lib.systems.flakeExposed;
    };
  };
}
