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
    expr = entities.node0.config.foo;
    expected = {
      common = 1;
      commonPriv = 1;
      group0 = 1;
      group0hw = 1;
      group0dc = 1;
      node0 = 1;
      node0hw = 1;
      node0dc = 1;
      group0priv = 1;
      node0priv = 1;
    };
  };
  groupNode0 = {
    expr = entities.groupNode0.config.foo;
    expected = {
      common = 1;
      commonPriv = 1;
      group0 = 1;
      group0hw = 1;
      group0dc = 1;
      groupNode0 = 1;
      groupNode0hw = 1;
      groupNode0dc = 1;
      group0priv = 1;
      groupNode0priv = 1;
    };
  };
  node0-home = {
    expr = entities.node0.config.home-manager.users.bar.baz;
    expected = {
      group0 = 1;
      node0 = 1;
    };
  };
  groupNode0-home = {
    expr = entities.groupNode0.config.home-manager.users.bar.baz;
    expected = {
      group0 = 1;
      groupNode0 = 1;
    };
  };
}
