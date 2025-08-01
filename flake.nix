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
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      lib' = import ./lib {
        inherit lib lib' self;
      };
      nix-unit = builtins.getFlake "github:nix-community/nix-unit/f0f20d931fa043905bc5fd50c5afa73f8eab67b3";
    in
    {
      lib = lib.removeAttrs lib' ([ "internal" ] ++ lib.attrNames lib'.internal);
      packages = lib'.forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          nixverse = pkgs.callPackage ./pkgs/nixverse {
            nixos-anywhere = inputs.nixos-anywhere.packages.${system}.nixos-anywhere;
            darwin-rebuild = inputs.nix-darwin.packages.${system}.darwin-rebuild or null;
          };
        in
        {
          inherit nixverse;
          default = nixverse;
        }
      );
      templates =
        let
          nixverse = {
            path = ./template;
            description = "A minimal flake using Nixverse";
            welcomeText = ''
              A minimal flake using Nixverse has been created.

              Update nodes/my-nodes to adapt to your own node.
            '';
          };
        in
        {
          inherit nixverse;
          default = nixverse;
        };
      devShells = lib'.forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          packages = [
            pkgs.nil
            pkgs.nixfmt-rfc-style
            pkgs.shfmt
            pkgs.shellcheck
            pkgs.nodePackages.bash-language-server
            pkgs.nodePackages.yaml-language-server
            nix-unit.packages.${system}.nix-unit
            self.packages.${system}.nixverse
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
          filter = [ ];
        in
        lib.concatMapAttrs (
          suiteName: type:
          let
            userFlake = {
              inputs = {
                nixpkgs-unstable = nixpkgs;
              }
              // lib.optionalAttrs (lib.pathExists ./tests/${suiteName}/inputs.nix) (
                lib'.internal.call (import ./tests/${suiteName}/inputs.nix) {
                  inherit lib lib' inputs;
                }
              );
              outPath = toString ./tests/${suiteName};
            };
          in
          lib.optionalAttrs
            (
              type == "directory"
              && lib.match "test.+" suiteName != null
              && (filter == [ ] || lib.elem suiteName filter)
            )
            (
              lib.mapAttrs' (testName: test: lib.nameValuePair "${suiteName}/${testName}" test) (
                import ./tests/${suiteName} {
                  inherit
                    lib
                    lib'
                    self
                    userFlake
                    ;
                }
              )
            )
        ) (builtins.readDir ./tests);
      checks = lib'.forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          tests =
            pkgs.runCommandNoCC "tests"
              {
                nativeBuildInputs = [ nix-unit.packages.${system}.nix-unit ];
                buildInputs = [ pkgs.cacert ];
                key = "";
              }
              ''
                export HOME="$(realpath .)"
                nix-unit --eval-store "$HOME" --extra-experimental-features flakes \
                ${
                  toString (
                    lib.mapAttrsToList (
                      name: input: "--override-input ${lib.escapeShellArg name} ${lib.escapeShellArg input}"
                    ) (lib.removeAttrs inputs [ "self" ])
                  )
                } --show-trace --flake ${self}#tests
                echo -n "$key" > $out
              '';
          key =
            # Discarding string context is safe, because we're not trying to read any store path contents.
            "check derived from ${baseNameOf (builtins.unsafeDiscardStringContext tests.drvPath)} is ok\n";
        in
        {
          tests = tests.overrideAttrs (old: {
            inherit key;
            outputHashAlgo = "sha256";
            outputHashMode = "flat";
            outputHash = builtins.hashString "sha256" key;
          });
        }
      );
    };
}
