{
  lib,
  lib',
  self,
  inputs,
  userFlakePath,
}:
{
  system,
  channel,
  os,
}:
let
  userFlakeInputs = lib.concatMapAttrs (
    name: rawInput:
    let
      homeModules = rawInput.homeManagerModules or rawInput.homeModules or { };
      input =
        lib.removeAttrs rawInput [
          "homeManagerModules"
          "nixosModules"
          "darwinModules"
        ]
        // {
          packages = rawInput.packages.${system} or { };
          legacyPackages = rawInput.legacyPackages.${system} or { };
          inherit homeModules;
          flakeModules = rawInput.flakeModules or { };
          modules =
            {
              nixos = rawInput.nixosModules or { };
              darwin = rawInput.darwinModules or { };
            }
            .${os};
        };
    in
    if channel != "unstable" && lib.hasSuffix "-unstable-${os}" name then
      { ${lib.removeSuffix "-${os}" name} = input; }
    else if channel != "unstable" && lib.hasSuffix "-unstable" name then
      { ${name} = input; }
    else if lib.hasSuffix "-${channel}-${os}" name then
      { ${lib.removeSuffix "-${channel}-${os}" name} = input; }
    else if lib.hasSuffix "-${channel}" name then
      { ${lib.removeSuffix "-${channel}" name} = input; }
    else if lib.hasSuffix "-none" name then
      { }
    else
      { ${name} = input; }
  ) (lib.removeAttrs inputs [ "self" ]);
  userFolderInputs =
    let
      getInputNames =
        dir:
        lib.optionals (lib.pathExists dir) (
          lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir))
        );
      inputNames = (
        getInputNames "${userFlakePath}/private/inputs" ++ getInputNames "${userFlakePath}/inputs"
      );
      getPackages =
        subdir: inputName:
        let
          pkgs = userFlakeInputs.nixpkgs.legacyPackages;
          pkgs' = lib.mapAttrs (name: paths: pkgs.callPackage (lib.head paths) { }) (
            lib'.allImportPathsInDirs [
              "${userFlakePath}/private/inputs/${inputName}/${subdir}"
              "${userFlakePath}/inputs/${inputName}/${subdir}"
            ]
          );
        in
        pkgs';
      getModules =
        inputName: moduleType:
        lib.mapAttrs
          (name: paths: {
            imports = paths;
          })
          (
            lib'.allImportPathsInDirs [
              "${userFlakePath}/private/inputs/${inputName}/modules/${moduleType}"
              "${userFlakePath}/inputs/${inputName}/modules/${moduleType}"
            ]
          );
    in
    lib.genAttrs inputNames (inputName: {
      packages = getPackages "packages" inputName;
      legacyPackages = getPackages "legacyPackages" inputName;
      modules = getModules inputName os;
      homeModules = getModules inputName "home";
      flakeModules = getModules inputName "flake";
    });
in
assert lib.assertMsg (userFlakeInputs ? nixpkgs)
  "Missing the flake input nixpkgs-${channel}${lib.optionalString (channel != "unstable") "-${os}"}";
lib.genAttrs (lib.unique (lib.attrNames userFlakeInputs ++ lib.attrNames userFolderInputs)) (
  inputName:
  userFlakeInputs.${inputName}
  // {
    packages =
      (userFlakeInputs.${inputName}.packages or { }) // (userFolderInputs.${inputName}.packages or { });
    legacyPackages =
      (userFlakeInputs.${inputName}.legacyPackages or { })
      // (userFolderInputs.${inputName}.legacyPackages or { });
    modules =
      (userFlakeInputs.${inputName}.modules or { }) // (userFolderInputs.${inputName}.modules or { });
    homeModules =
      (userFlakeInputs.${inputName}.homeModules or { })
      // (userFolderInputs.${inputName}.homeModules or { });
    flakeModules =
      (userFlakeInputs.${inputName}.flakeModules or { })
      // (userFolderInputs.${inputName}.flakeModules or { });
  }
)
