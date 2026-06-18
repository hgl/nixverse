{
  lib',
  userFlake,
  ...
}:
let
  outputs = lib'.load {
    inputs = userFlake.inputs // {
      self = userFlake;
    };
    flakePath = userFlake.outPath;
  };
  inherit (outputs.nixverse) nodes;
in
{
  inputs = {
    expr = {
      inherit (nodes.node0.config)
        pkg
        flakeOnlyPkg
        legacyPkg
        hasPublicOnlyLegacyPkg
        hasExtraLegacyPkg
        flakeOnlyModuleValue
        ;
    };
    expected = {
      pkg = "flake-pkg";
      flakeOnlyPkg = "flake-only-pkg";
      legacyPkg = "legacy-pkg";
      hasPublicOnlyLegacyPkg = false;
      hasExtraLegacyPkg = false;
      flakeOnlyModuleValue = "flake-only-module";
    };
  };
}
