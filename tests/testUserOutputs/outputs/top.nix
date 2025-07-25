{ inputs, ... }:
{
  template = 1;
  legacyPackages.x86_64-linux.foo = inputs ? nixpkgs-unstable;
}
