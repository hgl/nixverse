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
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      {
        lib,
        lib',
        config,
        ...
      }:
      {
        imports = [
          flake-parts.flakeModules.partitions
        ];
        _module.args.lib' = import ./lib {
          inherit lib lib' self;
        };
        systems = lib.systems.flakeExposed;
        flake = {
          lib = lib.removeAttrs lib' ([ "internal" ] ++ lib.attrNames lib'.internal);
          templates = {
            nixverse = {
              path = ./template;
              description = "A minimal flake using Nixverse";
              welcomeText = ''
                A minimal flake using Nixverse has been created.

                Update nodes/my-nodes to adapt to your own node.
              '';
            };
            default = config.flake.templates.nixverse;
          };
        };
        perSystem =
          {
            config,
            inputs',
            pkgs,
            ...
          }:
          {
            packages = {
              nixverse = pkgs.callPackage ./pkgs/nixverse {
                nixos-anywhere = inputs'.nixos-anywhere.packages.nixos-anywhere;
                darwin-rebuild = inputs'.nix-darwin.packages.darwin-rebuild or null;
              };
              default = config.packages.nixverse;
            };
            devShells.default = pkgs.mkShellNoCC {
              name = "shell";
              packages = [
                pkgs.nil
                pkgs.nixfmt
                pkgs.shfmt
                pkgs.shellcheck
                pkgs.nodePackages.bash-language-server
                pkgs.nodePackages.yaml-language-server
                pkgs.nix-unit
                config.packages.nixverse
              ];
            };
          };
        partitionedAttrs.checks = "tests";
        partitionedAttrs.tests = "tests";
        partitions.tests.extraInputsFlake = ./tests;
        partitions.tests.module = ./tests/flake-module.nix;
      }
    );
}
