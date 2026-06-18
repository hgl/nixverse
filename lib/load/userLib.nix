{
  lib,
  lib',
  inputs,
  userFlakePath,
}:
let
  userLibArgs = {
    inherit (inputs.nixpkgs-unstable) lib;
    lib' = userLib;
    inherit inputs;
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
