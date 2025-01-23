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
      lib' = import ./lib.nix libArgs;
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
      load = import ./load {
        inherit lib lib';
      };
      lib = lib';
      packages = lib'.forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          nixverse = pkgs.callPackage (import ./packages/nixverse) {
            nixos-anywhere = self.inputs.nixos-anywhere.packages.${system}.nixos-anywhere;
            darwin-rebuild = self.inputs.nix-darwin.packages.${system}.darwin-rebuild;
          };
        in
        {
          inherit nixverse;
          default = nixverse;
        }
      );
      templates.nixverse = template;
      templates.default = template;
      devShells = lib'.forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages =
              with pkgs;
              [
                nil
                nixfmt-rfc-style
                shfmt
                shellcheck
                nodePackages.bash-language-server
                (writeShellScriptBin "run" ''
                  for i in $(seq 1 $((1 + $RANDOM % 4))); do
                    echo doing step $i
                    sleep 0.$(($RANDOM % 999))
                  done
                '')
              ]
              ++ [ self.packages.${system}.nixverse ];
          };
        }
      );
      tests =
        let
          testLoad =
            names: flake:
            lib'.mapListToAttrs (
              name:
              lib.nameValuePair name (
                self.load (
                  {
                    outPath = ./tests/${name};
                  }
                  // flake
                )
              )
            ) names;
        in
        testLoad
          [
            "lib"
            "group"
            "selfRef"
            "crossRef"
            "groupEmpty"
            "groupEmptyCommon"
            "groupEmptyDeep"
            "confPath"
            "hwconfPath"
            "private"
          ]
          {
            inputs = {
              nixpkgs-unstable = nixpkgs;
            };
          }
        // testLoad [ "nodeArgs" ] {
          inputs = {
            nixpkgs-unstable = nixpkgs;
            custom-unstable = {
              value = 1;
            };
          };
        }
        // testLoad [ "home" ] {
          inputs = {
            nixpkgs-unstable = nixpkgs;
            home-manager-unstable = builtins.getFlake "github:nix-community/home-manager/bd65bc3cde04c16755955630b344bc9e35272c56";
          };
        };
    };
}
