{
  lib,
  lib',
  self,
  inputs,
  userFlakePath,
}:
let
  userFlake =
    inputs.self or (throw ''
      When loading nixverse, you must pass all the flake output arguments,
      and not just `self.inputs`.

      For example:

          outputs =
            inputs@{ nixverse, ... }:
            nixverse.lib.load {
              inherit inputs;
              flakePath = ./.;
            };

      To avoid an infinite recursion, *DO NOT* pass `self.inputs` and
      *DO NOT* pass `inherit (self) inputs`, but pass the output function
      arguments as `inputs` like above.
    '');
  userInputs = lib.mapAttrs (
    name: input:
    let
      homeModules = input.homeManagerModules or input.homeModules or null;
    in
    lib.removeAttrs input [
      "homeManagerModules"
    ]
    // lib.optionalAttrs (homeModules != null) {
      inherit homeModules;
    }
  ) (lib.removeAttrs inputs [ "self" ]);
  userLib = import ./userLib.nix {
    inherit
      lib
      lib'
      userInputs
      userFlakePath
      ;
  };
  getUserPkgs = import ./getUserPkgs.nix {
    inherit
      lib
      lib'
      self
      userFlakePath
      ;
  };
  getUserInputs = import ./getUserInputs.nix {
    inherit
      lib
      lib'
      self
      inputs
      userFlakePath
      ;
  };
  userModules = import ./userModules.nix {
    inherit
      lib
      lib'
      userFlakePath
      ;
  };
  userNodes = lib.mapAttrs (
    nodeName: node:
    {
      host = lib.removeAttrs node [
        "configuration"
        "dir"
        "diskConfigPaths"
        "sshHostKeyPath"
        "recursiveFoldParentNames"
      ];
      group = lib.removeAttrs node [
        "recursiveFoldChildNames"
      ];
    }
    .${node.type}
  ) nodes;
  nodes = lib.mapAttrs (
    nodeName: rawNode:
    {
      host = import ./host.nix {
        inherit
          lib
          lib'
          userInputs
          userFlakePath
          userLib
          userModules
          rawNode
          getUserPkgs
          getUserInputs
          ;
        userNodes = lib.concatMapAttrs (
          name: node:
          {
            ${name} = node;
          }
          // lib.optionalAttrs (name == nodeName) {
            current = node;
          }
        ) userNodes;
      };
      group = import ./group.nix {
        inherit
          lib
          lib'
          userNodes
          rawNode
          ;
      };
    }
    .${rawNode.type}
  ) rawNodes;
  rawNodes = import ./rawNodes.nix {
    inherit
      lib
      lib'
      userFlakePath
      ;
  };
  userOutputs = import ./userOutputs.nix {
    inherit
      lib
      lib'
      self
      userInputs
      userFlake
      userFlakePath
      userLib
      getUserPkgs
      userModules
      nodes
      userNodes
      ;
  };
in
assert lib.assertMsg (
  userInputs ? nixpkgs-unstable
) "Missing the required flake input nixpkgs-unstable";
userOutputs
