lib: with lib; {
  mapListToAttrs = f: list: listToAttrs (map f list);
  concatMapAttrsToList = f: attrs: concatLists (mapAttrsToList f attrs);
  concatMapListToAttrs = f: list: listToAttrs (concatMap f list);
}
