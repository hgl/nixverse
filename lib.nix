{ lib, lib' }:
with lib;
{
  forAllSystems = lib.genAttrs lib.systems.flakeExposed;
  callWithOptionalArgs =
    f: args: if lib.isFunction f then f (lib.intersectAttrs (lib.functionArgs f) args) else f;
  mapListToAttrs = f: list: listToAttrs (map f list);
  concatMapAttrsToList = f: attrs: concatLists (mapAttrsToList f attrs);
  concatMapListToAttrs = f: list: listToAttrs (concatMap f list);
  filterRecursive =
    pred: sl:
    if isAttrs sl then
      lib'.concatMapListToAttrs (
        name:
        let
          v = sl.${name};
        in
        if pred name v then
          [
            (nameValuePair name (lib'.filterRecursive pred v))
          ]
        else
          [ ]
      ) (attrNames sl)
    else if isList sl then
      map (lib'.filterRecursive pred) sl
    else
      sl;
}
