config':
{
  lib,
  runCommand,
  makeWrapper,
  nixverse,
}:
runCommand "nixverse"
  {
    meta.mainProgram = "nixverse";
    nativeBuildInputs = [ makeWrapper ];
  }
  ''
    makeWrapper ${lib.getExe nixverse} $out/bin/nixverse \
      --set FLAKE_DIR '${config'.flakeSource}'
  ''
