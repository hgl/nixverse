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
in
{
  rootBundleModuleCollision = {
    expr = outputs.nixverse.nodes.node0.config.networking.hostName;
    expectedError = {
      type = "ThrownError";
      msg = "Module `collide` exists in both `modules/nixos` and `bundles/sample/modules/nixos`";
    };
  };
}
