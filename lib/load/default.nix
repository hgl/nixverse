{
  lib,
  lib',
  self,
  rawInputs,
  userFlakePath,
}:
let
  userFlake =
    rawInputs.self or (throw ''
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
  inputs = lib.mapAttrs (
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
  ) (lib.removeAttrs rawInputs [ "self" ]);
  userLib = import ./userLib.nix {
    inherit
      lib
      lib'
      inputs
      userFlakePath
      ;
  };
  userBundleNames = import ./userBundleNames.nix {
    inherit
      lib
      userFlakePath
      ;
  };
  getUserPkgs = import ./getUserPkgs.nix {
    inherit
      lib
      lib'
      self
      userFlakePath
      userBundleNames
      ;
  };
  getUserInputs = import ./getUserInputs.nix {
    inherit
      lib
      inputs
      ;
  };
  getUserModules = import ./getUserModules.nix {
    inherit
      lib
      lib'
      userFlakePath
      userBundleNames
      ;
  };
  userOutputsNodes = lib.mapAttrs (
    _: node:
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
  userNodes = lib.mapAttrs (
    _: node:
    {
      host = lib.removeAttrs node [
        "lib"
        "lib'"
        "pkgs"
        "pkgs'"
      ];
      group = lib.removeAttrs node [
        "lib"
        "lib'"
        "pkgs"
        "pkgs'"
      ];
    }
    .${node.type}
  ) userOutputsNodes;
  nodes = lib.mapAttrs (
    nodeName: rawNode:
    {
      host = import ./host.nix {
        inherit
          lib
          lib'
          userFlakePath
          userLib
          getUserModules
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
      inputs
      userFlake
      userFlakePath
      userLib
      getUserPkgs
      getUserModules
      nodes
      userNodes
      userOutputsNodes
      ;
  };
in
assert lib.assertMsg (
  inputs ? nixpkgs-unstable
) "Missing the required flake input nixpkgs-unstable";
userOutputs
