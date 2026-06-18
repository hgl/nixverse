{ inputs, ... }:
{
  x86_64-linux = [
    inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.gawk
  ];
}
