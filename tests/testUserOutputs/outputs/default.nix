{
  inputs,
  nodes,
  ...
}:
{
  flake = {
    template = 1;
    legacyPackages.x86_64-linux.foo = inputs ? nixpkgs-unstable;
    legacyPackages.x86_64-linux.nodePkgs = nodes.node0.pkgs ? gawk;
    legacyPackages.x86_64-linux.nodePkgs' = nodes.node0.pkgs'.foo;
    legacyPackages.x86_64-linux.nodeLib = nodes.node0.lib ? concatLines;
    legacyPackages.x86_64-linux.nodeLib' = nodes.node0.lib' == { };
  };
  systems = nodes.node0.lib.systems.flakeExposed;
  perSystem =
    {
      pkgs,
      pkgs',
      ...
    }:
    {
      legacyPackages.bar = pkgs ? gawk;
      legacyPackages.perSystemPkgs' = pkgs'.foo;
    };
}
