{
  lib,
  lib',
}:
{
  forAllSystems = lib.genAttrs lib.systems.flakeExposed;
  mapListToAttrs = f: list: lib.listToAttrs (map f list);
  concatMapAttrsToList = f: attrs: lib.concatLists (lib.mapAttrsToList f attrs);
  concatMapListToAttrs = f: list: lib.listToAttrs (lib.concatMap f list);

  filterRecursive =
    pred: sl:
    if lib.isAttrs sl then
      lib'.concatMapListToAttrs (
        name:
        let
          v = sl.${name};
        in
        if pred name v then
          [
            (lib.nameValuePair name (lib'.filterRecursive pred v))
          ]
        else
          [ ]
      ) (lib.attrNames sl)
    else if lib.isList sl then
      map (lib'.filterRecursive pred) sl
    else
      sl;
}
