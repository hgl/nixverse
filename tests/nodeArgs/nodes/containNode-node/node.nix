{
  inputs,
  common,
  nodes,
  lib,
}:
{
  override = "node";
  final = {
    inputs = inputs.custom.value;
    common = lib.intersectAttrs {
      common = 1;
      overrid = 1;
    } common;
    nodes = {
      current = {
        inherit (nodes.current) name override;
      };
      containNode-node = nodes.containNode-node.groupNodeOverride;
      containNode-group-0 = nodes.containNode-group-0.groupNode;
    };
  };
}
