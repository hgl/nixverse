{
  lib,
  lib',
  userEntities,
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
  parents = lib.genAttrs rawEntity.parentNames (name: userEntities.${name});
  groups = lib.genAttrs rawEntity.groupNames (name: userEntities.${name});
  children = lib.genAttrs rawEntity.childNames (name: userEntities.${name});
  descendants = lib.genAttrs rawEntity.descendantNames (name: userEntities.${name});
  nodes = lib.genAttrs rawEntity.nodeNames (name: userEntities.${name});
}
