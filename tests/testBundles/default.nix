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
  bundles = {
    expr = {
      inherit (nodes.node0.config)
        bundlePkgInPkgs
        publicOnlyPkgInPkgs
        extraPkgInPkgs
        bundleModuleValue
        publicOnlyModuleValue
        privateModuleValue
        hasBundleInput
        folderOnlyPkgInPkgs
        folderOnlyModuleValue
        folderOsModuleValue
        folderOverrideModuleValue
        ;
    };
    expected = {
      bundlePkgInPkgs = "private-x86_64-linux";
      publicOnlyPkgInPkgs = "public-only-x86_64-linux";
      extraPkgInPkgs = "extra-x86_64-linux";
      bundleModuleValue = "private-module";
      publicOnlyModuleValue = "public-only-module";
      privateModuleValue = "private-only-module";
      hasBundleInput = false;
      folderOnlyPkgInPkgs = "folder-only-x86_64-linux";
      folderOnlyModuleValue = "folder-only-module";
      folderOsModuleValue = "folder-os-module";
      folderOverrideModuleValue = "folder-nixos-module";
    };
  };
}
