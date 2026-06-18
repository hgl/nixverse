{
  inputs,
  nodes,
  ...
}:
{
  x86_64-linux = {
    foo = inputs ? nixpkgs-unstable;
    nodePkgs = nodes.node0.pkgs ? gawk;
    nodePkgs' = nodes.node0.pkgs'.foo;
    nodeLib = nodes.node0.lib ? concatLines;
    nodeLib' = nodes.node0.lib' == { };
  };
}
