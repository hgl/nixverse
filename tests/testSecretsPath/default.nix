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
  inherit (outputs.nixverse) entities;
in
{
  node0 = {
    expr = entities.node0.config.sops.defaultSopsFile;
    expected = "${userFlake}/nodes/node0/secrets/default.yaml";
  };
  groupNode0 = {
    expr = entities.groupNode0.config.sops.defaultSopsFile;
    expected = "${userFlake}/nodes/group0/groupNode0/secrets/default.yaml";
  };
}
