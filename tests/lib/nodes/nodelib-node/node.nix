{ lib' }:
{
  os = "nixos";
  channel = "unstable";
  top = lib'.top;
  x = lib'.x;
  node = lib'.node;
}
