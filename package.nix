{
  jq,
  writeShellApplication,
  lib,
}:
writeShellApplication {
  name = "nixverse";
  runtimeInputs = [ jq ];
  text = lib.readFile ./nixverse.bash;
}
