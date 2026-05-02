{
  lib',
  userFlake,
  ...
}:
let
  outputs = lib'.load {
    inputs = userFlake.inputs // {
      self = userFlake;
    };
    flakePath = userFlake.outPath;
  };
  inherit (outputs.nixverse) nodes;
in
{
  node0 = {
    expr = nodes.node0.config.sops.defaultSopsFile;
    expected = "${userFlake}/nodes/node0/secrets/default.yaml";
  };
  groupNode0 = {
    expr = nodes.groupNode0.config.sops.defaultSopsFile;
    expected = "${userFlake}/nodes/group0/groupNode0/secrets/default.yaml";
  };
}
