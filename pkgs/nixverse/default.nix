{
  lib,
  nix,
  runCommand,
  bash,
  coreutils,
  git,
  util-linux, # for getopt and uuidgen
  findutils,
  gnumake,
  openssh,
  sops,
  ssh-to-age,
  jq,
  rsync,
  nixos-anywhere,
  nixos-rebuild-ng,
  darwin-rebuild,
  buildGoModule,
}:
let
  parallel-run = buildGoModule {
    name = "nixverse";
    src = ../..;
    vendorHash = "sha256-osBO3GTp7JvK3+Sz678cKUgl+10FJI9n6AVLpBTeIrA=";
    subPackages = [ "cmd/parallel-run" ];
  };
in
runCommand "nixverse"
  {
    meta.mainProgram = "nixverse";
  }
  ''
    mkdir -p $out/{bin,lib}
    cp -r ${./library} $out/lib/nixverse

    substituteInPlace $out/lib/nixverse/Makefile \
      --subst-var-by out $out
    substitute ${./nixverse.sh} $out/bin/nixverse \
      --subst-var-by shell ${lib.getExe bash} \
      --subst-var-by out $out \
      --subst-var-by path ${
        lib.makeBinPath (
          [
            bash
            coreutils
            git
            util-linux
            nix
            findutils
            gnumake
            openssh
            sops
            ssh-to-age
            jq
            rsync
            nixos-anywhere
            nixos-rebuild-ng
            parallel-run
            (builtins.placeholder "out")
          ]
          ++ lib.optional (darwin-rebuild != null) darwin-rebuild
        )
      }
    chmod a=rx $out/bin/nixverse
  ''
