{
  lib,
  lib',
  self,
  inputs,
  userFlakePath,
  getModules,
}:
{
  system,
  channel,
  os,
  moduleType,
}:
let
  userFlakeInputs = lib.concatMapAttrs (
    name: rawInput:
    let
      input =
        lib.removeAttrs rawInput [
          "homeManagerModules"
          "homeModules"
          "nixosModules"
          "darwinModules"
          "flakeModules"
        ]
        // {
          packages = rawInput.packages.${system} or { };
          legacyPackages = rawInput.legacyPackages.${system} or { };
          modules = {
            nixos = rawInput.nixosModules or { };
            darwin = rawInput.darwinModules or { };
            home = rawInput.homeManagerModules or rawInput.homeModules or { };
            flake = rawInput.flakeModules or { };
          }.${moduleType};
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
      getInputModules =
        inputName: moduleType:
        getModules [
          "${userFlakePath}/private/inputs/${inputName}/modules"
          "${userFlakePath}/inputs/${inputName}/modules"
        ] moduleType;
    in
    lib.genAttrs inputNames (inputName: {
      modules = getInputModules inputName moduleType;
    });
in
assert lib.assertMsg (userFlakeInputs ? nixpkgs)
  "Missing the flake input nixpkgs-${channel}${lib.optionalString (channel != "unstable") "-${os}"}";
lib.genAttrs (lib.unique (lib.attrNames userFlakeInputs ++ lib.attrNames userFolderInputs)) (
  inputName:
  userFlakeInputs.${inputName} or { }
  // {
    modules =
      (userFlakeInputs.${inputName}.modules or { }) // (userFolderInputs.${inputName}.modules or { });
  }
)
