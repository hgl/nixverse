{
  lib,
  lib',
}:
{
  forAllSystems = lib.genAttrs lib.systems.flakeExposed;
  mapListToAttrs = f: list: lib.listToAttrs (map f list);
  concatMapAttrsToList = f: attrs: lib.concatLists (lib.mapAttrsToList f attrs);
  concatMapListToAttrs = f: list: lib.zipAttrsWith (name: values: lib.last values) (map f list);
  internal = import ./internal.nix {
    inherit lib lib';
  };
}
