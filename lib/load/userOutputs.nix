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
  raw =
    lib'.dirEntryImportPaths
      [
        "${userFlakePath}/outputs"
        "${userFlakePath}/private/outputs"
      ]
      [ "top" "perSystem" ];
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
  userOutputs = self.inputs.flake-parts.lib.mkFlake { inherit (userFlake) inputs; } {
    imports =
      map (path: {
        flake = {
          config = lib'.call (import path) {
            inherit nodes;
            self = userFlake;
            inputs = userFlake.inputs;
            lib = userFlake.inputs.nixpkgs-unstable.lib;
            lib' = userLib;
            nixosModules' = userModules.nixos;
            darwinModules' = userModules.darwin;
            homeModules' = userModules.home;
          };
        };
      }) raw.top or [ ]
      ++ map (path: {
        perSystem =
          { system, ... }:
          let
            pkgs = userFlake.inputs.nixpkgs-unstable.legacyPackages.${system};
          in
          {
            config = lib'.call (import path) {
              inherit system pkgs nodes;
              self = userFlake;
              inputs = userFlake.inputs;
              lib = userFlake.inputs.nixpkgs-unstable.lib;
              lib' = userLib;
              pkgs' = userPkgs pkgs;
            };
          };
      }) raw.perSystem or [ ];
    systems = lib.systems.flakeExposed;
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
  };
  nixosConfigurations = loadConfigurations "nixos";
  darwinConfigurations = loadConfigurations "darwin";
}
// userOutputs
