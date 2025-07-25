{
  lib',
  userFlake,
  ...
}:
let
  outputs = lib'.load {
    flake = userFlake;
    flakePath = userFlake.outPath;
  };
  inherit (outputs.nixverse) entities;
in
{
  node0 = {
    expr = {
      inherit (entities.node0)
        type
        name
        os
        channel
        foo
        ;
      parents = {
        group0 = entities.node0.parents.group0.name;
      };
    };
    expected = {
      type = "node";
      name = "node0";
      os = "nixos";
      channel = "master";
      foo = {
        group0 = 1;
        group0priv = 1;
        node0 = 1;
        node0priv = 1;
      };
      parents = {
        group0 = "group0";
      };
    };
  };
  group0 = {
    expr = {
      inherit (entities.group0) type name;
      children = {
        node0 = entities.group0.children.node0.name;
      };
    };
    expected = {
      type = "group";
      name = "group0";
      children = {
        node0 = "node0";
      };
    };
  };
  groupNode0 = {
    expr = {
      inherit (entities.groupNode0)
        type
        name
        os
        channel
        foo
        ;
      parents = {
        group0 = entities.groupNode0.parents.group0.name;
      };
    };
    expected = {
      type = "node";
      name = "groupNode0";
      os = "darwin";
      channel = "foo";
      foo = {
        group0 = 1;
        group0priv = 1;
        groupNode0priv = 1;
      };
      parents = {
        group0 = "group0";
      };
    };
  };
  args = {
    expr = entities.args.deploy.targetHost;
    expected = "1 baz 1 args x86_64-linux";
  };
}
