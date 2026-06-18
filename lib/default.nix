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
  concatMapAttrsToList = f: attrs: lib.concatLists (lib.mapAttrsToList f attrs);
  concatMapListToAttrs = f: list: lib.zipAttrsWith (name: values: lib.last values) (map f list);
  load =
    {
      inputs,
      flakePath,
    }:
    import ./load {
      inherit
        lib
        lib'
        self
        ;
      rawInputs = inputs;
      # This argument needs to be explicitly passed because of a nix limitation
      # https://github.com/hercules-ci/flake-parts/issues/148
      userFlakePath = flakePath;
    };
}
// internal
