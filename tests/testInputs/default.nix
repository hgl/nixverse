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
        publicOnlyLegacyPkg
        extraLegacyPkg
        publicOnlyPkg
        extraPkg
        inputModuleValue
        flakeOnlyModuleValue
        publicOnlyModuleValue
        privateModuleValue
        folderOnlyPkg
        folderOnlyModuleValue
        ;
    };
    expected = {
      pkg = "private-x86_64-linux";
      flakeOnlyPkg = "flake-only-pkg";
      legacyPkg = "private-legacy-x86_64-linux";
      publicOnlyLegacyPkg = "public-only-legacy-x86_64-linux";
      extraLegacyPkg = "extra-legacy-x86_64-linux";
      publicOnlyPkg = "public-only-x86_64-linux";
      extraPkg = "extra-x86_64-linux";
      inputModuleValue = "private-module";
      flakeOnlyModuleValue = "flake-only-module";
      publicOnlyModuleValue = "public-only-module";
      privateModuleValue = "private-only-module";
      folderOnlyPkg = "folder-only-x86_64-linux";
      folderOnlyModuleValue = "folder-only-module";
    };
  };
}
