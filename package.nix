{
  lib,
  runCommand,
  bash,
  coreutils,
  gnumake,
  openssh,
  sops,
  ssh-to-age,
  jq,
  yq,
  nixos-anywhere,
  nixos-rebuild,
}:
runCommand "nixverse" { } ''
  mkdir -p $out/{bin,share/nixverse}
  cp ${./partition.bash} $out/share/nixverse/partition
  cp ${./Makefile} $out/share/nixverse/Makefile
  substitute ${./nixverse.bash} $out/bin/nixverse \
    --subst-var-by shell "${lib.getExe bash}" \
    --subst-var-by PATH ${
      lib.makeBinPath [
        bash
        coreutils
        gnumake
        openssh
        sops
        ssh-to-age
        jq
        yq
        nixos-anywhere
        nixos-rebuild
      ]
    } \
    --subst-var-by out $out
  chmod a=rx $out/bin/nixverse
''
