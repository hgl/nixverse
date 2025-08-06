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
  empty = {
    expr = rawEntities;
    expectedError = {
      type = "ThrownError";
      msg = "Group is empty: ${userFlake}/nodes/group/group.nix";
    };
  };
}
