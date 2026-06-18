{
  lib,
  userFlakePath,
}:
let
  getBundleNames =
    dir:
    lib.optionals (lib.pathExists dir) (
      lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir))
    );
in
lib.unique (
  getBundleNames "${userFlakePath}/private/bundles" ++ getBundleNames "${userFlakePath}/bundles"
)
