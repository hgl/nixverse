{
  lib,
  lib',
  nodes,
  rawEntity,
}:
lib.removeAttrs rawEntity [
  "parentNames"
  "groupNames"
  "childNames"
  "descendantNames"
  "nodeNames"
]
// {
  parents = lib.genAttrs rawEntity.parentNames (name: nodes.${name});
  groups = lib.genAttrs rawEntity.groupNames (name: nodes.${name});
  children = lib.genAttrs rawEntity.childNames (name: nodes.${name});
  descendants = lib.genAttrs rawEntity.descendantNames (name: nodes.${name});
  nodes = lib.genAttrs rawEntity.nodeNames (name: nodes.${name});
}
