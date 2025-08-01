{
  lib,
  lib',
  self,
  userFlake,
  userFlakePath,
  userLib,
  userPkgs,
  userModules,
  entities,
  nodes,
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
        inherit (userFlake) inputs;
        specialArgs = {
          inherit nodes;
          self = userFlake;
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
          lib = userFlake.inputs.nixpkgs-unstable.lib;
          lib' = userLib;
        };
        systems = lib.systems.flakeExposed;
        perSystem =
          { config, system, ... }:
          let
            pkgs = userFlake.inputs.nixpkgs-unstable.legacyPackages.${system};
          in
          {
            _module.args = {
              inherit pkgs;
              pkgs' = userPkgs pkgs;
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
      entities
      nodes
      ;
    inherit (userFlake) inputs;
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
