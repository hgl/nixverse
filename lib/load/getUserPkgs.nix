{
  lib,
  lib',
  self,
  userFlakePath,
}:
pkgs:
let
  getInputNames =
    dir:
    lib.optionals (lib.pathExists dir) (
      lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir))
    );
  inputNames = lib.unique (
    getInputNames "${userFlakePath}/private/inputs" ++ getInputNames "${userFlakePath}/inputs"
  );
  privateInputPackageDirs = map (
    inputName: "${userFlakePath}/private/inputs/${inputName}/packages"
  ) inputNames;
  publicInputPackageDirs = map (
    inputName: "${userFlakePath}/inputs/${inputName}/packages"
  ) inputNames;
  rootPackagePaths = lib'.allImportPathsInDirs [
    "${userFlakePath}/private/pkgs"
    "${userFlakePath}/pkgs"
  ];
  inputPackagePathsByInput = lib.genAttrs inputNames (
    inputName:
    lib'.allImportPathsInDirs [
      "${userFlakePath}/private/inputs/${inputName}/packages"
      "${userFlakePath}/inputs/${inputName}/packages"
    ]
  );
  inputPackagePaths = lib'.allImportPathsInDirs (privateInputPackageDirs ++ publicInputPackageDirs);
  rootInputPackageCollisions = lib.intersectLists (lib.attrNames rootPackagePaths) (
    lib.attrNames inputPackagePaths
  );
  rootInputPackageCollision = lib.head rootInputPackageCollisions;
  rootInputPackageCollisionInput = lib.findFirst (
    inputName: lib.hasAttr rootInputPackageCollision inputPackagePathsByInput.${inputName}
  ) null inputNames;
  callPackage = pkgs.newScope {
    inherit pkgs' lib';
    nixverse = self.packages.${pkgs.stdenv.hostPlatform.system}.nixverse;
  };
  pkgs' = lib.mapAttrs (name: paths: callPackage (lib.head paths) { }) (
    rootPackagePaths // inputPackagePaths
  );
in
assert lib.assertMsg (rootInputPackageCollisions == [ ])
  "Package `${rootInputPackageCollision}` exists in both the root packages directory and input `${rootInputPackageCollisionInput}`'s packages directory";
pkgs'
