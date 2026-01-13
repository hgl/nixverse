{
  self,
  lib,
  lib',
  inputs,
  ...
}:
{
  imports = [
    inputs.nix-unit.modules.flake.default
  ];
  flake.tests =
    let
      filter = [ ];
    in
    lib.concatMapAttrs (
      suiteName: type:
      let
        userFlake = {
          inputs = {
            nixpkgs-unstable = inputs.nixpkgs;
          }
          // lib.optionalAttrs (lib.pathExists ./${suiteName}/inputs.nix) (
            lib'.internal.call (import ./${suiteName}/inputs.nix) {
              inherit lib lib' inputs;
            }
          );
          outPath = toString ./${suiteName};
        };
      in
      lib.optionalAttrs
        (
          type == "directory"
          && lib.match "test.+" suiteName != null
          && (filter == [ ] || lib.elem suiteName filter)
        )
        (
          lib.mapAttrs' (testName: test: lib.nameValuePair "${suiteName}/${testName}" test) (
            import ./${suiteName} {
              inherit
                lib
                lib'
                self
                userFlake
                ;
            }
          )
        )
    ) (builtins.readDir ./.);
  perSystem = {
    nix-unit = {
      inputs = lib.removeAttrs inputs [ "self" ];
      allowNetwork = true;
    };
  };
}
