node:
{
  lib,
  runCommand,
  bash,
  nixverse,
}:
runCommand "config"
  {
    meta.mainProgram = "config";
  }
  ''
    mkdir -p $out/bin
    substitute ${./config.sh} $out/bin/config \
      --subst-var-by shell ${lib.getExe bash} \
      --subst-var-by node_name '${node.name}' \
      --subst-var-by path ${
        lib.makeBinPath [
          nixverse
        ]
      }
    chmod a=rx $out/bin/config
  ''
