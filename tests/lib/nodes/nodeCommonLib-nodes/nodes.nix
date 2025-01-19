{
  nodeCommonLib-nodes-0 =
    {
      lib,
      inputs,
      lib',
    }:
    {
      os = "nixos";
      channel = "unstable";
      final = {
        lib = builtins.elem "x86_64-linux" lib.systems.flakeExposed;
        inputs = inputs.nixpkgsLib.lib.global;
        libP = {
          inherit (lib') top;
          common = lib'.common or null;
          node = lib'.node or null;
        };
      };
    };
}
