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
      load = import ./load.nix {
        inherit lib self lib';
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
              ]
              ++ [ self.packages.${system}.nixverse ];
          };
        }
      );
    };
}
