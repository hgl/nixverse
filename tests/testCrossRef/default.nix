{
  lib,
  lib',
  userFlake,
  ...
}:
let
  rawNodes = import ../../lib/load/rawNodes.nix {
    inherit lib lib';
    userFlakePath = userFlake.outPath;
  };
in
{
  crossRef = {
    expr = rawNodes.crossRef0;
    expectedError = {
      type = "ThrownError";
      msg = "cyclic group containment: crossRef0 ⊇ crossRef1 ⊇ crossRef0";
    };
  };
}
