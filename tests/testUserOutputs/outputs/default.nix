{ inputs, ... }:
{
  flake = {
    template = 1;
    legacyPackages.x86_64-linux.foo = inputs ? nixpkgs-unstable;
  };
  perSystem =
    { pkgs, ... }:
    {
      legacyPackages.bar = pkgs ? gawk;
    };
}
