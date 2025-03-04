{
  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixverse = {
      url = "github:hgl/nixverse";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs =
    {
      self,
      nixpkgs-unstable,
      nixverse,
      ...
    }:
    nixverse.load self {
      nixverse = {
        inheritLib = true;
      };
      devShells = nixverse.lib.forAllSystems (
        system:
        let
          pkgs = nixpkgs-unstable.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              nil
              nixfmt-rfc-style
              nixverse.packages.${system}.nixverse
            ];
          };
        }
      );
    };
}
