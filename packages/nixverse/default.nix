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
  buildGoModule,
}:
runCommand "nixverse"
  {
    meta.mainProgram = "nixverse";
  }
  ''
    mkdir -p $out/{bin,libexec/nixverse,lib/nixverse}
    cp ${./partition.sh} $out/libexec/nixverse/partition
    cp ${./secrets.mk} $out/lib/nixverse/secrets.mk
    substitute ${./nixverse.sh} $out/bin/nixverse \
      --subst-var-by shell ${lib.getExe bash} \
      --subst-var-by out $out \
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
          (buildGoModule {
            name = "nixverse";
            src = ../..;
            vendorHash = "sha256-osBO3GTp7JvK3+Sz678cKUgl+10FJI9n6AVLpBTeIrA=";
            subPackages = [ "cmd/parallel" ];
          })
        ]
      }
    chmod a=rx $out/bin/nixverse
  ''
