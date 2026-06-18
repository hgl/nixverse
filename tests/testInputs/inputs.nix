{
  sample-unstable = {
    packages.x86_64-linux = {
      pkg = "flake-pkg";
      flakeOnlyPkg = "flake-only-pkg";
    };
    legacyPackages.x86_64-linux = {
      legacyPkg = "legacy-pkg";
    };
    nixosModules = {
      flakeOnlyModule = {
        flakeOnlyModuleValue = "flake-only-module";
      };
    };
  };
}
