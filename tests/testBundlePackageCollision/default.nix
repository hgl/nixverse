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
  bundlePackageCollision = {
    expr = outputs.nixverse.nodes.node0.config.pkg;
    expectedError = {
      type = "ThrownError";
      msg = "Package `pkg` exists in both `pkgs` and `bundles/sample/pkgs`";
    };
  };
}
