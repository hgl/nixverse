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
  folderInputs = {
    expr = {
      inherit (nodes.node0.config)
        pkg
        flakeOnlyPkg
        legacyPkg
        hasPublicOnlyLegacyPkg
        hasExtraLegacyPkg
        inputModuleValue
        flakeOnlyModuleValue
        publicOnlyModuleValue
        privateModuleValue
        folderOnlyHasPkg
        folderOnlyModuleValue
        folderOsModuleValue
        folderOverrideModuleValue
        ;
    };
    expected = {
      pkg = "flake-pkg";
      flakeOnlyPkg = "flake-only-pkg";
      legacyPkg = "legacy-pkg";
      hasPublicOnlyLegacyPkg = false;
      hasExtraLegacyPkg = false;
      inputModuleValue = "private-module";
      flakeOnlyModuleValue = "flake-only-module";
      publicOnlyModuleValue = "public-only-module";
      privateModuleValue = "private-only-module";
      folderOnlyHasPkg = false;
      folderOnlyModuleValue = "folder-only-module";
      folderOsModuleValue = "folder-os-module";
      folderOverrideModuleValue = "folder-nixos-module";
    };
  };
}
