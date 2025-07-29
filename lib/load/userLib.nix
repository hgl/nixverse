{
  lib,
  lib',
  userFlake,
  userFlakePath,
}:
let
  userLibArgs = {
    inherit (userFlake.inputs.nixpkgs-unstable) lib;
    lib' = userLib;
    inherit (userFlake) inputs;
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
