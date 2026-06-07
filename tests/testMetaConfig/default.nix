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
    expr = {
      inherit (nodes.node0)
        type
        name
        os
        system
        channel
        foo
        ;
      parents = {
        group0 = nodes.node0.parents.group0.name;
      };
    };
    expected = {
      type = "host";
      name = "node0";
      os = "nixos";
      system = "x86_64-linux";
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
      inherit (nodes.group0) type name;
      children = {
        node0 = nodes.group0.children.node0.name;
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
      inherit (nodes.groupNode0)
        type
        name
        os
        system
        channel
        foo
        ;
      parents = {
        group0 = nodes.groupNode0.parents.group0.name;
      };
    };
    expected = {
      type = "host";
      name = "groupNode0";
      os = "darwin";
      system = "aarch64-darwin";
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
    expr = {
      inherit (nodes.args.deploy) targetHost;
      pkg = nodes.args.config.pkg;
      inherit (nodes.args.config) userNodePackages;
    };
    expected = {
      targetHost = "1 baz 1 args x86_64-linux";
      pkg = "x86_64-linux";
      userNodePackages = "false false false false";
    };
  };
}
