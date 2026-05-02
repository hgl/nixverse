{
  lib,
  lib',
  userNodes,
  rawNode,
}:
lib.removeAttrs rawNode [
  "parentNames"
  "groupNames"
  "childNames"
  "descendantNames"
  "hostNames"
]
// {
  parents = lib.genAttrs rawNode.parentNames (name: userNodes.${name});
  groups = lib.genAttrs rawNode.groupNames (name: userNodes.${name});
  children = lib.genAttrs rawNode.childNames (name: userNodes.${name});
  descendants = lib.genAttrs rawNode.descendantNames (name: userNodes.${name});
  hosts = lib.genAttrs rawNode.hostNames (name: userNodes.${name});
}
