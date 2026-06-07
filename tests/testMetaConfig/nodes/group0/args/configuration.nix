{
  lib,
  inputs',
  nodes,
  ...
}:
let
  hasNodeAttr = name: if builtins.hasAttr name nodes.current then "true" else "false";
in
{
  options = {
    pkg = lib.mkOption {
      type = lib.types.str;
    };
    userNodePackages = lib.mkOption {
      type = lib.types.str;
    };
  };

  config = {
    pkg = inputs'.sample.packages.pkg;
    userNodePackages = "${hasNodeAttr "pkgs"} ${hasNodeAttr "pkgs'"} ${hasNodeAttr "lib"} ${hasNodeAttr "lib'"}";
  };
}
