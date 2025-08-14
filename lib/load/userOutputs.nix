{
  lib,
  lib',
  self,
  userInputs,
  userFlake,
  userFlakePath,
  userLib,
  getUserPkgs,
  userModules,
  userEntities,
  entities,
}:
let
  userFlakeModules =
    (lib'.importPathsInDirs
      [
        userFlakePath
        "${userFlakePath}/private"
      ]
      [ "outputs" ]
    ).outputs;
  loadConfigurations =
    os:
    lib.concatMapAttrs (
      name: entity:
      if entity.type == "node" && entity.os == os then
        {
          ${name} = entity.configuration;
        }
      else
        { }
    ) entities;
  userOutputs =
    let
      inherit (self.inputs) flake-parts;
    in
    flake-parts.lib.mkFlake
      {
        inputs = userInputs // {
          self = userFlake;
        };
        specialArgs = {
          nodes = userEntities;
          nixosModules' = userModules.nixos;
          darwinModules' = userModules.darwin;
          homeModules' = userModules.home;
          flakeModules' = userModules.flake;
        };
      }
      {
        imports = [
          ./modules/flake/makefileInputs.nix
        ]
        ++ userFlakeModules;
        _module.args = {
          lib = userInputs.nixpkgs-unstable.lib;
          lib' = userLib;
          getPkgs' = getUserPkgs;
        };
        perSystem =
          { config, system, ... }:
          let
            pkgs = userInputs.nixpkgs-unstable.legacyPackages.${system};
          in
          {
            _module.args = {
              inherit pkgs;
              pkgs' = getUserPkgs pkgs;
            };
            apps = {
              nixverse = {
                type = "app";
                program = self.packages.${system}.nixverse;
              };
              default = config.apps.nixverse;
              make = {
                type = "app";
                program = pkgs.callPackage (import ./packages/make.nix { inherit (config) makefileInputs; }) { };
              };
            };
          };
      };
in
assert lib.assertMsg (
  userOutputs.nixosConfigurations == { }
) "Do not specify the nixosConfigurations flake output, it is generated automatically";
assert lib.assertMsg (
  userOutputs.darwinConfigurations or { } == { }
) "Do not specify the darwinConfigurations flake output, it is generated automatically";
assert lib.assertMsg (
  userOutputs.lib or { } == { }
) "Do not specify the lib flake output, it is generated automatically";
assert lib.assertMsg (
  userOutputs.nixverse or { } == { }
) "Do not specify the nixverse flake output, it is used internally by nixverse";
{
  lib = userLib;
  nixverse = {
    inherit
      lib
      lib'
      userEntities
      entities
      ;
    inherit (userFlake) inputs;
    getSecrets = import ./getSecrets.nix {
      inherit
        lib
        lib'
        userInputs
        userLib
        userEntities
        entities
        ;
    };
  }
  // import ../../pkgs/nixverse/output.nix {
    inherit
      lib
      lib'
      userLib
      userInputs
      userFlakePath
      userEntities
      entities
      ;
  };
  nixosConfigurations = loadConfigurations "nixos";
  darwinConfigurations = loadConfigurations "darwin";
}
// lib.removeAttrs userOutputs [
  "lib"
  "nixosConfigurations"
  "darwinConfigurations"
  "makefileInputs"
]
