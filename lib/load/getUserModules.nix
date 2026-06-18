{
  lib,
  lib',
  userFlakePath,
  userBundleNames,
}:
moduleType:
let
  rootModulePaths = [
    "${userFlakePath}/modules"
    "${userFlakePath}/private/modules"
  ];
  bundleModulePaths =
    (map (bundleName: "${userFlakePath}/bundles/${bundleName}/modules") userBundleNames)
    ++ (map (bundleName: "${userFlakePath}/private/bundles/${bundleName}/modules") userBundleNames);
  getModuleDir =
    modulePath:
    let
      moduleName = lib.removeSuffix ".nix" (baseNameOf modulePath);
      moduleDir =
        if lib.hasSuffix "/${moduleName}/default.nix" modulePath then
          lib.removeSuffix "/${moduleName}/default.nix" modulePath
        else
          lib.removeSuffix "/${moduleName}.nix" modulePath;
    in
    lib.removePrefix "${userFlakePath}/" moduleDir;
  getModulePaths =
    paths: type:
    let
      typePaths = lib'.allImportPathsInDirs (map (path: "${path}/${type}") paths);
      osPaths = lib.optionalAttrs (lib.elem type [
        "nixos"
        "darwin"
      ]) (lib'.allImportPathsInDirs (map (path: "${path}/os") paths));
      moduleNameCollisions = lib.intersectAttrs osPaths typePaths;
      moduleNameCollision = lib.head (lib.attrNames moduleNameCollisions);
      osModuleDir = getModuleDir (lib.head osPaths.${moduleNameCollision});
      typeModuleDir = getModuleDir (lib.head typePaths.${moduleNameCollision});
    in
    assert lib.assertMsg (moduleNameCollisions == { })
      "Module `${moduleNameCollision}` exists in both `${osModuleDir}` and `${typeModuleDir}`";
    osPaths // typePaths;
  getModules =
    paths: type:
    lib.mapAttrs (name: paths: {
      imports = paths;
    }) (getModulePaths paths type);
  rootModules' = getModules rootModulePaths moduleType;
  bundleModules' = getModules bundleModulePaths moduleType;
  moduleNameCollisions = lib.intersectAttrs rootModules' bundleModules';
  moduleNameCollision = lib.head (lib.attrNames moduleNameCollisions);
  rootModuleDir = getModuleDir (lib.head (getModulePaths rootModulePaths moduleType).${moduleNameCollision});
  bundleModuleDir = getModuleDir (lib.head (getModulePaths bundleModulePaths moduleType).${moduleNameCollision});
in
assert lib.assertMsg (moduleNameCollisions == { })
  "Module `${moduleNameCollision}` exists in both `${rootModuleDir}` and `${bundleModuleDir}`";
rootModules' // bundleModules'
