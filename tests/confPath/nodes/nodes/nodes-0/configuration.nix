{ node, ... }:
{

  nixpkgs.hostPlatform = "x86_64-linux";
  nixverse-test = {
    bar2 = node.x;
  };
}
