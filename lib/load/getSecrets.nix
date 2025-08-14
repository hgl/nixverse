{
  lib,
  lib',
  userInputs,
  userLib,
  userEntities,
  entities,
}:
raw:
let
  secretsAttrs = lib'.call raw {
    lib = userInputs.nixpkgs-unstable.lib;
    lib' = userLib;
    inputs = userInputs;
    nodes = userEntities;
    secrets = secretsAttrs;
  };
  secrets =
    (lib.evalModules {
      modules = [
        ./modules/nixos/secrets.nix
        {
          config = secretsAttrs;
        }
      ];
    }).config;
  nodeNameAttrs = lib.concatMapAttrs (
    entityName: _:
    let
      entity = entities.${entityName};
    in
    {
      node = {
        ${entityName} = true;
      };
      group = lib.mapAttrs (nodeName: node: true) entity.nodes;
    }
    .${entity.type}
  ) secrets.nodes;
  nodesSecrets = lib.mapAttrs (
    nodeName: _:
    let
      node = entities.${nodeName};
    in
    node.recursiveFoldParentNames (
      acc: parentNames: _:
      lib.recursiveUpdate (builtins.foldl' (
        acc: parentName: lib.recursiveUpdate acc secrets.nodes.${parentName} or { }
      ) { } parentNames) acc
    ) secrets.nodes.${nodeName} or { }
  ) nodeNameAttrs;
in
{
  config = secrets // {
    nodes = secrets.nodes // nodesSecrets;
  };
  nodeNames = lib.attrNames nodeNameAttrs;
}
