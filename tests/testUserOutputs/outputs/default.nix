{ lib, inputs, ... }:
{
  flake = {
    template = 1;
    legacyPackages.x86_64-linux.foo = inputs ? nixpkgs-unstable;
  };
  systems = lib.systems.flakeExposed;
  perSystem =
    { pkgs, ... }:
    {
      legacyPackages.bar = pkgs ? gawk;
    };
}
