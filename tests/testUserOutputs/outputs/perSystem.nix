{ pkgs, ... }:
{
  legacyPackages.bar = pkgs ? gawk;
}
