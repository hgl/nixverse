{
  lib,
  lib',
  self,
  userInputs,
  userFlake,
  userFlakePath,
  userLib,
  getUserModules,
  userNodes,
  userOutputsNodes,
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
      name: node:
      if node.type == "host" && node.os == os then
        {
          ${name} = node.configuration;
        }
      else
        { }
    ) nodes;
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
          nodes = userOutputsNodes;
          nixosModules' = getUserModules "nixos";
          darwinModules' = getUserModules "darwin";
          homeModules' = getUserModules "home";
          flakeModules' = getUserModules "flake";
        };
      }
      {
        imports = [
          ./modules/flake/makefileInputs.nix
        ]
        ++ userFlakeModules;
        perSystem =
          { config, system, ... }:
          let
            pkgs = userInputs.nixpkgs-unstable.legacyPackages.${system};
          in
          {
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
      userNodes
      nodes
      ;
    inherit (userFlake) inputs;
    getSecrets = import ./getSecrets.nix {
      inherit
        lib
        lib'
        userInputs
        userLib
        userNodes
        nodes
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
      userNodes
      nodes
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
