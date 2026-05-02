{
  lib,
  lib',
  userInputs,
  userLib,
  userNodes,
  nodes,
}:
raw:
let
  secretsAttrs = lib'.call raw {
    lib = userInputs.nixpkgs-unstable.lib;
    lib' = userLib;
    inputs = userInputs;
    nodes = userNodes;
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
    nodeName: _:
    let
      node = nodes.${nodeName};
    in
    {
      host = {
        ${nodeName} = true;
      };
      group = lib.mapAttrs (nodeName: node: true) node.hosts;
    }
    .${node.type}
  ) secrets.nodes;
  nodesSecrets = lib.mapAttrs (
    nodeName: _:
    let
      node = nodes.${nodeName};
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
