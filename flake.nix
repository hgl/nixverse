{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
      libArgs = {
        inherit lib lib';
      };
      lib' = import ./lib libArgs;
      template = {
        path = ./template;
        description = "Nixverse template";
        welcomeText = ''
          foobar
          line2
        '';
      };
    in
    {
      lib = lib';
      load = import ./load {
        inherit lib lib' self;
      };
      loadPkgs' = import ./loadPkgs {
        inherit lib lib' self;
      };
      packages = lib'.forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          nixverse = pkgs.callPackage (import ./pkgs/nixverse) {
            nixos-anywhere = self.inputs.nixos-anywhere.packages.${system}.nixos-anywhere;
            darwin-rebuild = self.inputs.nix-darwin.packages.${system}.darwin-rebuild or null;
          };
        in
        {
          inherit nixverse;
          default = nixverse;
        }
      );
      templates = {
        nixverse = template;
        default = template;
      };
      devShells = lib'.forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pkgs' = self.packages.${system};
          packages = with pkgs; [
            nixd
            nixfmt-rfc-style
            shfmt
            shellcheck
            nodePackages.bash-language-server
            nodePackages.yaml-language-server
            ssh-to-age
            sops
            yq
            jq
            util-linux # for experimenting with getopt
            pkgs'.nixverse
          ];
        in
        {
          default = derivation {
            name = "shell";
            inherit system packages;
            builder = "${pkgs.bash}/bin/bash";
            outputs = [ "out" ];
            stdenv = pkgs.writeTextDir "setup" ''
              set -e

              for p in $packages; do
                PATH=$p/bin:$PATH
              done
            '';
          };
        }
      );
      tests =
        let
          testLoad =
            names: flake: outputs:
            lib'.mapListToAttrs (
              name:
              lib.nameValuePair name (
                import ./load/load.nix {
                  inherit
                    lib
                    lib'
                    self
                    outputs
                    ;
                  flake = {
                    outPath = ./tests/${name};
                  } // flake;
                }
              )
            ) names;
        in
        {
          inherit lib lib';
          tests =
            testLoad
              [
                "lib"
                "group"
                "groups"
                "selfRef"
                "crossRef"
                "groupEmpty"
                "groupEmptyCommon"
                "groupEmptyDeep"
                "disallowedNodeValueType"
                "disallowedNodeValueChannel"
                "wrongNodeValue"
                "confPath"
                "hwconfPath"
                "files"
                "private"
              ]
              {
                inputs = {
                  nixpkgs-unstable = nixpkgs;
                };
              }
              { }
            // testLoad [ "secretsPath" ] {
              inputs = {
                nixpkgs-unstable = nixpkgs;
                sops-nix-unstable = builtins.getFlake "github:Mic92/sops-nix/07af005bb7d60c7f118d9d9f5530485da5d1e975";
              };
            } { }
            // testLoad [ "nodeArgs" ] {
              inputs = {
                nixpkgs-unstable = nixpkgs;
                custom-unstable = {
                  value = 1;
                };
              };
            } { }
            // testLoad [ "home" ] {
              inputs = {
                nixpkgs-unstable = nixpkgs;
                home-manager-unstable = builtins.getFlake "github:nix-community/home-manager/bd65bc3cde04c16755955630b344bc9e35272c56";
              };
            } { };
        };
    };
}
