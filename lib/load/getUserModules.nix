{
  getModules,
  userFlakePath,
}:
moduleType:
getModules [
  "${userFlakePath}/modules"
  "${userFlakePath}/private/modules"
] moduleType
