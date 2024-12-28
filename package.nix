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
let
  nixverse =
    runCommand "nixverse"
      {
        meta.mainProgram = "nixverse";
      }
      ''
        mkdir -p $out/{bin,libexec/nixverse,lib/nixverse}
        cp ${./partition.bash} $out/libexec/nixverse/partition
        cp ${./secrets.mk} $out/lib/nixverse/secrets.mk
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
      '';
in
nixverse
