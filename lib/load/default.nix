{
  lib,
  lib',
  self,
  userFlake,
  userFlakePath,
}:
let
  userLib = import ./userLib.nix {
    inherit
      lib
      lib'
      userFlake
      userFlakePath
      ;
  };
  userPkgs = import ./userPkgs.nix {
    inherit
      lib
      lib'
      self
      userFlake
      userFlakePath
      ;
  };
  userModules = import ./userModules.nix {
    inherit
      lib
      lib'
      userFlake
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
          userFlake
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
      userFlake
      userFlakePath
      ;
  };
  userOutputs = import ./userOutputs.nix {
    inherit
      lib
      lib'
      self
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
userOutputs
