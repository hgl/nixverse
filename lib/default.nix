{
  lib,
  lib',
  self,
}:
let
  internal = import ./internal.nix {
    inherit lib lib';
  };
in
{
  inherit internal;
  forAllSystems = lib.genAttrs lib.systems.flakeExposed;
  mapListToAttrs = f: list: lib.listToAttrs (map f list);
  concatMapAttrsToList = f: attrs: lib.concatLists (lib.mapAttrsToList f attrs);
  concatMapListToAttrs = f: list: lib.zipAttrsWith (name: values: lib.last values) (map f list);
  load =
    {
      inputs,
      flakePath,
    }:
    import ./load {
      inherit lib lib' self;
      userInputs = lib.mapAttrs (
        name: input:
        let
          homeModules = input.homeManagerModules or input.homeModules or null;
        in
        lib.removeAttrs input [
          "homeManagerModules"
        ]
        // lib.optionalAttrs (homeModules != null) {
          inherit homeModules;
        }
      ) (lib.removeAttrs inputs [ "self" ]);
      userFlake =
        inputs.self or (throw ''
          When loading nixverse, you must pass all the flake output arguments,
          and not just `self.inputs`.

          For example:

              outputs =
                inputs@{ nixverse, ... }:
                nixverse.lib.load {
                  inherit inputs;
                  flakePath = ./.;
                };

          To avoid an infinite recursion, *DO NOT* pass `self.inputs` and
          *DO NOT* pass `inherit (self) inputs`, but pass the output function
          arguments as `inputs` like above.
        '');
      # This argument needs to be explicitly passed because of a nix limitation
      # https://github.com/hercules-ci/flake-parts/issues/148
      userFlakePath = flakePath;
    };
}
// internal
