{
  lib,
  lib',
  userFlake,
  ...
}:
let
  rawEntities = import ../../lib/load/rawEntities.nix {
    inherit lib lib';
    userFlakePath = userFlake.outPath;
  };
in
{
  crossRef = {
    expr = rawEntities.crossRef0;
    expectedError = {
      type = "ThrownError";
      msg = "cyclic group containment: crossRef0 ⊇ crossRef1 ⊇ crossRef0";
    };
  };
}
