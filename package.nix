{
  self,
  lib,
  entities,
}:
{
  jq,
  writeShellApplication,
  writeText,
}:
writeShellApplication {
  name = "nixverse";
  runtimeInputs = [ jq ];
  runtimeEnv = {
    entitiesPath = writeText "nixverse-entities" (
      builtins.toJSON (
        map (
          entity:
          self.lib.filterRecursive (_: v: !(lib.isFunction v)) (
            lib.removeAttrs entity [
              "inputs"
              "lib"
              "modules"
            ]
          )
        ) entities
      )
    );
  };
  text = lib.readFile ./nixverse.bash;
}
