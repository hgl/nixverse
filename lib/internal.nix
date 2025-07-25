{
  lib,
  lib',
}:
{
  call = f: args: if lib.isFunction f then f args else f;
  optionalPath = path: lib.optional (lib.pathExists path) path;
  optionalImportPath =
    dir: name:
    let
      paths = lib'.optionalPath "${dir}/${name}/default.nix" ++ lib'.optionalPath "${dir}/${name}.nix";
      n = lib.length paths;
      path = lib.head paths;
    in
    assert lib.assertMsg (n <= 1) "Both ${path} and ${lib.elemAt paths 1} exist, only one is allowed";
    lib.optional (n != 0) path;
  dirEntryImportPaths =
    dirs: names:
    lib.zipAttrsWith (name: paths: lib.concatLists paths) (
      lib.concatMap (
        dir:
        map (name: {
          ${name} = lib'.optionalImportPath dir name;
        }) names
      ) dirs
    );
  allDirEntryImportPaths =
    dirs:
    lib.zipAttrs (
      lib.concatMap (
        dir:
        lib.optional (lib.pathExists dir) (
          let
            attrs = lib.zipAttrs (
              lib'.concatMapAttrsToList (
                name: type:
                let
                  basename = lib.removeSuffix ".nix" name;
                  defaultPath = "${dir}/${name}/default.nix";
                in
                if basename != name then
                  [
                    {
                      ${basename} = "${dir}/${name}";
                    }
                  ]
                else if lib.pathExists defaultPath then
                  [
                    {
                      ${name} = defaultPath;
                    }
                  ]
                else
                  [ ]
              ) (builtins.readDir dir)
            );
          in
          lib.mapAttrs (
            name: paths:
            let
              path = lib.head paths;
            in
            assert lib.assertMsg (
              lib.length paths == 1
            ) "Both ${path} and ${lib.elemAt paths 1} exist, only one is allowed";
            path
          ) attrs
        )
      ) dirs
    );
}
