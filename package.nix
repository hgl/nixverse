{
  lib,
  runCommand,
  bash,
  coreutils,
  findutils,
  gnumake,
  openssh,
  sops,
  ssh-to-age,
  jq,
  yq,
  nixos-anywhere,
  nixos-rebuild,
  darwin-rebuild,
}:
runCommand "nixverse" { } ''
  mkdir -p $out/{bin,share/nixverse}
  cp ${./partition.bash} $out/share/nixverse/partition
  cp ${./Makefile} $out/share/nixverse/Makefile
  substitute ${./nixverse.bash} $out/bin/nixverse \
    --subst-var-by shell "${lib.getExe bash}" \
    --subst-var-by path ${
      lib.makeBinPath [
        bash
        coreutils
        findutils
        gnumake
        openssh
        sops
        ssh-to-age
        jq
        yq
        nixos-anywhere
        nixos-rebuild
        darwin-rebuild
        (builtins.placeholder "out")
      ]
    } \
    --subst-var-by out $out
  chmod a=rx $out/bin/nixverse
''
