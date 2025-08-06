{
  lib,
  lib',
  userInputs,
  userFlakePath,
}:
let
  userLibArgs = {
    inherit (userInputs.nixpkgs-unstable) lib;
    lib' = userLib;
    inputs = userInputs;
  };
  userLib =
    builtins.foldl' (acc: path: lib.recursiveUpdate acc (lib'.call (import path) userLibArgs)) { }
      (lib'.importPathsInDirs
        [
          userFlakePath
          "${userFlakePath}/private"
        ]
        [ "lib" ]
      ).lib;
in
userLib
