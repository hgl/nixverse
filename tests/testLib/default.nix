{
  lib',
  ...
}:
let
  publicDir = toString ./dirAttrs/public;
  privateDir = toString ./dirAttrs/private;
in
{
  dirEntryImportPaths = {
    expr =
      lib'.dirEntryImportPaths
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
  dirEntryImportPathsEmpty = {
    expr =
      lib'.dirEntryImportPaths
        [
          publicDir
        ]
        [ "non-exist" ];
    expected = {
      non-exist = [ ];
    };
  };
  allDirEntryImportPaths = {
    expr = lib'.allDirEntryImportPaths [
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
  allDirEntryImportPathsDup =
    let
      dir = toString ./dupDirAttrs;
    in
    {
      expr = lib'.allDirEntryImportPaths [
        dir
      ];
      expectedError = {
        type = "ThrownError";
        msg = "Both ${dir}/a/default.nix and ${dir}/a.nix exist, only one is allowed";
      };
    };
}
