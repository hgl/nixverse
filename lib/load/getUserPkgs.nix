{
  lib,
  lib',
  self,
  getUserInputs,
  userFlakePath,
  userBundleNames,
}:
channel:
pkgs:
let
  system = pkgs.stdenv.hostPlatform.system;
  os = if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "nixos";
  inputs' = getUserInputs {
    inherit
      system
      channel
      os
      ;
    moduleType = os;
  };
  rootPackagePaths = [
    "${userFlakePath}/private/pkgs"
    "${userFlakePath}/pkgs"
  ];
  bundlePackagePaths =
    (map (bundleName: "${userFlakePath}/private/bundles/${bundleName}/pkgs") userBundleNames)
    ++ (map (bundleName: "${userFlakePath}/bundles/${bundleName}/pkgs") userBundleNames);
  getPackagePaths = paths: lib'.allImportPathsInDirs paths;
  getPackageDir =
    packagePath:
    let
      packageName = lib.removeSuffix ".nix" (baseNameOf packagePath);
      packageDir =
        if lib.hasSuffix "/default.nix" packagePath then
          lib.removeSuffix "/default.nix" packagePath
        else
          lib.removeSuffix "/${packageName}.nix" packagePath;
    in
    lib.removePrefix "${userFlakePath}/" packageDir;
  rootPackages' = getPackagePaths rootPackagePaths;
  bundlePackages' = getPackagePaths bundlePackagePaths;
  packageNameCollisions = lib.intersectAttrs rootPackages' bundlePackages';
  packageNameCollision = lib.head (lib.attrNames packageNameCollisions);
  rootPackageDir = getPackageDir (lib.head rootPackages'.${packageNameCollision});
  bundlePackageDir = getPackageDir (lib.head bundlePackages'.${packageNameCollision});
  callPackage = pkgs.newScope {
    inherit pkgs' lib' inputs';
    nixverse = self.packages.${system}.nixverse;
  };
  pkgs' = lib.mapAttrs (name: paths: callPackage (lib.head paths) { }) (
    rootPackages' // bundlePackages'
  );
in
assert lib.assertMsg (packageNameCollisions == { })
  "Package `${packageNameCollision}` exists in both `${rootPackageDir}` and `${bundlePackageDir}`";
pkgs'
