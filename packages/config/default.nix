node:
{
  lib,
  runCommand,
  bash,
  nixos-rebuild,
  darwin-rebuild,
}:
runCommand "config"
  {
    meta.mainProgram = "config";
  }
  ''
    mkdir -p $out/bin
    substitute ${./config.bash} $out/bin/config \
      --subst-var-by shell ${lib.getExe bash} \
      --subst-var-by flake '${node.flake}' \
      --subst-var-by node_name '${node.name}' \
      --subst-var-by node_os '${node.os}' \
      --subst-var-by path ${
        lib.makeBinPath [
          nixos-rebuild
          darwin-rebuild
        ]
      }
    chmod a=rx $out/bin/config
  ''
