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
      flake,
      flakePath,
    }:
    import ./load {
      inherit lib lib' self;
      userFlake = flake;
      # This argument needs to be explicitly passed by a user because of a nix limitation
      # https://github.com/hercules-ci/flake-parts/issues/148
      userFlakePath = flakePath;
    };
}
// internal
