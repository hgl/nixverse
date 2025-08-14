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
  userEntities = lib.mapAttrs (
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
      node = import ./node.nix {
        inherit
          lib
          lib'
          userInputs
          userFlakePath
          userLib
          userModules
          rawEntity
          getUserPkgs
          ;
        userEntities = lib.concatMapAttrs (
          name: entity:
          {
            ${name} = entity;
          }
          // lib.optionalAttrs (name == entityName) {
            current = entity;
          }
        ) userEntities;
      };
      group = import ./group.nix {
        inherit
          lib
          lib'
          userEntities
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
      getUserPkgs
      userModules
      entities
      userEntities
      ;
  };
in
assert lib.assertMsg (
  userInputs ? nixpkgs-unstable
) "Missing the required flake input nixpkgs-unstable";
userOutputs
