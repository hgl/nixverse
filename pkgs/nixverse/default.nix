{
  lib,
  runCommand,
  nix,
  bash,
  coreutils,
  util-linux, # for getopt
  gnumake,
  openssh,
  sops,
  ssh-to-age,
  yq,
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
    mkdir -p $out/{bin,lib/nixverse/secrets}
    cp ${./secrets/Makefile} $out/lib/nixverse/secrets/Makefile
    cp ${./secrets/module.nix} $out/lib/nixverse/secrets/module.nix
    cp ${./secrets/template.nix} $out/lib/nixverse/secrets/template.nix

    substitute ${./nixverse.sh} $out/bin/nixverse \
      --subst-var-by shell ${lib.getExe bash} \
      --subst-var-by out $out \
      --subst-var-by path ${
        lib.makeBinPath ([
          nix
          bash
          coreutils
          util-linux
          gnumake
          openssh
          sops
          ssh-to-age
          yq
          nixos-anywhere
          nixos-rebuild-ng
          parallel-run
          (builtins.placeholder "out")
        ]
        # TODO: re-enable this after it no longer defaults to older version of nix
        # https://github.com/nix-darwin/nix-darwin/pull/1549
        # ++ lib.optional (darwin-rebuild != null) darwin-rebuild
        )
      }
    chmod a=rx $out/bin/nixverse
  ''
