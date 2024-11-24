lib:
with lib;
let
  filterRecursive =
    pred: sl:
    if isAttrs sl then
      listToAttrs (
        concatMap (
          name:
          let
            v = sl.${name};
          in
          if pred name v then
            [
              (nameValuePair name (filterRecursive pred v))
            ]
          else
            [ ]
        ) (attrNames sl)
      )
    else if isList sl then
      map (filterRecursive pred) sl
    else
      sl;
in
{
  inherit filterRecursive;
  mapListToAttrs = f: list: listToAttrs (map f list);
  concatMapAttrsToList = f: attrs: concatLists (mapAttrsToList f attrs);
  concatMapListToAttrs = f: list: listToAttrs (concatMap f list);
}
