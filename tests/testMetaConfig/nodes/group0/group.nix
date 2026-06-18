{
  common =
    { lib, ... }:
    {
      options.foo = lib.mkOption {
        type = lib.types.attrsOf lib.types.int;
      };
      config = {
        system = lib.mkDefault "x86_64-linux";
        channel = lib.mkDefault "unstable";
        foo = {
          group0 = 1;
        };
      };
    };
  groupNode0 = {
    system = "aarch64-darwin";
  };
  node0 = {
    foo = {
      node0 = 1;
    };
  };
  args =
    {
      lib',
      lib,
      inputs',
      nodes,
      ...
    }:
    {
      deploy.targetHost = "${toString (lib ? concatLines)} ${lib'.bar} ${
        toString (inputs' ? nixpkgs)
      } ${nodes.current.name} ${nodes.current.config.nixpkgs.hostPlatform.system}";
    };
}
