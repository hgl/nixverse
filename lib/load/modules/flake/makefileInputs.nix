{ lib, flake-parts-lib, ... }:
let
  inherit (lib)
    mkOption
    types
    ;
  inherit (flake-parts-lib)
    mkTransposedPerSystemModule
    ;
in
mkTransposedPerSystemModule {
  name = "makefileInputs";
  option = mkOption {
    type = types.listOf types.package;
    default = [ ];
    description = ''
      Inputs to add to the Makefile's `$PATH` at runtime.
    '';
  };
  file = ./makefileInputs.nix;
}
