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
  userPkgs = import ./userPkgs.nix {
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
  nodes = lib.mapAttrs (
    entityName: entity:
    {
      node = lib.removeAttrs entity [
        "configuration"
        "dir"
        "diskConfigPaths"
        "sshHostKeyPath"
        "recursiveFoldParentNames"
      ];
      group = lib.removeAttrs entity [
        "recursiveFoldChildNames"
      ];
    }
    .${entity.type}
  ) entities;
  entities = lib.mapAttrs (
    entityName: rawEntity:
    {
      node = import ./loadNode.nix {
        inherit
          lib
          lib'
          userInputs
          userFlakePath
          userLib
          userPkgs
          userModules
          nodes
          rawEntity
          ;
      };
      group = import ./loadGroup.nix {
        inherit
          lib
          lib'
          nodes
          rawEntity
          ;
      };
    }
    .${rawEntity.type}
  ) rawEntities;
  rawEntities = import ./rawEntities.nix {
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
      userPkgs
      userModules
      entities
      nodes
      ;
  };
in
assert lib.assertMsg (
  userInputs ? nixpkgs-unstable
) "Missing the required flake input nixpkgs-unstable";
userOutputs
