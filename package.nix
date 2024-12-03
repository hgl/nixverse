{
  lib,
  runCommand,
  jq,
  nixos-anywhere,
}:
runCommand "nixverse" { } ''
  mkdir -p $out/{bin,share/nixverse}
  cp ${./partition.bash} $out/share/nixverse/partition
  substitute ${./nixverse.bash} $out/bin/nixverse \
    --subst-var-by PATH ${
      lib.makeBinPath [
        jq
        nixos-anywhere
      ]
    } \
    --subst-var-by out $out
  chmod a=rx $out/bin/nixverse
''
