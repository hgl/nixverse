{ lib' }:
{
  os = "nixos";
  channel = "unstable";
  top = lib'.top;
}
