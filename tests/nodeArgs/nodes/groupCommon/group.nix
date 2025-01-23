{
  common =
    { common, nodes }:
    {
      os = "nixos";
      channel = "unstable";
      common = {
        override = common.override;
        nodes = {
          current = {
            inherit (nodes.current) name override;
          };
          groupCommon-0 = nodes.groupCommon-0.override;
        };
      };
      override = "common";
    };
  groupCommon-0 =
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
          override = 1;
        } common;
        nodes = {
          current = {
            inherit (nodes.current) name override;
          };
          groupCommon-0 = nodes.groupCommon-0.override;
        };
      };
    };
}
