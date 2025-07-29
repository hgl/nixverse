{
  lib',
  ...
}:
let
  publicDir = toString ./dirAttrs/public;
  privateDir = toString ./dirAttrs/private;
in
{
  importPathsInDirs = {
    expr =
      lib'.importPathsInDirs
        [
          publicDir
          privateDir
        ]
        [ "a" "b" "public" ];
    expected = {
      a = [
        "${publicDir}/a.nix"
        "${privateDir}/a/default.nix"
      ];
      b = [
        "${publicDir}/b/default.nix"
        "${privateDir}/b.nix"
      ];
      public = [
        "${publicDir}/public.nix"
      ];
    };
  };
  importPathsInDirsEmpty = {
    expr =
      lib'.importPathsInDirs
        [
          publicDir
        ]
        [ "non-exist" ];
    expected = {
      non-exist = [ ];
    };
  };
  allImportPathsInDirs = {
    expr = lib'.allImportPathsInDirs [
      publicDir
      privateDir
    ];
    expected = {
      a = [
        "${publicDir}/a.nix"
        "${privateDir}/a/default.nix"
      ];
      b = [
        "${publicDir}/b/default.nix"
        "${privateDir}/b.nix"
      ];
      public = [
        "${publicDir}/public.nix"
      ];
      private = [
        "${privateDir}/private/default.nix"
      ];
    };
  };
  allImportPathsInDirsDup =
    let
      dir = toString ./dupDirAttrs;
    in
    {
      expr = lib'.allImportPathsInDirs [
        dir
      ];
      expectedError = {
        type = "ThrownError";
        msg = "Both ${dir}/a/default.nix and ${dir}/a.nix exist, only one is allowed";
      };
    };
}
