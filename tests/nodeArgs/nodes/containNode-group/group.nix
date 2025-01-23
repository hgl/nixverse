{
  common =
    { common, nodes }:
    {
      os = "nixos";
      channel = "unstable";
      override = "common";
      common = {
        override = common.override;
        nodes = {
          current = {
            inherit (nodes.current) name override;
          };
          containNode-nodeOverride = nodes.containNode-node.override;
          containNode-group-0Override = nodes.containNode-group-0.override;
        };
      };
    };
  containNode-node =
    {
      inputs,
      common,
      nodes,
      lib,
    }:
    {
      override = "groupNodeOverride";
      groupNodeOverride = {
        common = lib.intersectAttrs {
          common = 1;
          override = 1;
        } common;
        nodes = {
          current = {
            inherit (nodes.current) name override;
          };
          containNode-nodeOverride = nodes.containNode-node.override;
          containNode-group-0Override = nodes.containNode-group-0.override;
        };
      };
    };
  containNode-group-0 =
    {
      inputs,
      common,
      nodes,
      lib,
    }:
    {
      override = "groupNode";
      groupNode = {
        common = lib.intersectAttrs {
          common = 1;
          overrid = 1;
        } common;
        nodes = {
          current = {
            inherit (nodes.current) name override;
          };
          containNode-nodeOverride = nodes.containNode-node.override;
          containNode-group-0Override = nodes.containNode-group-0.override;
        };
      };
    };
}
