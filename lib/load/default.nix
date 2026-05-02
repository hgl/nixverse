{
  lib,
  lib',
  self,
  userInputs,
  userFlake,
  userFlakePath,
}:
let
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
