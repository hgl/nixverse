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
  rootInputPackageCollision = {
    expr = outputs.nixverse.nodes.node0.config.pkg;
    expectedError = {
      type = "ThrownError";
      msg = "Package `pkg` exists in both the root packages directory and input `sample`'s packages directory";
    };
  };
}
