{
  nodeLib-group-0 =
    {
      lib,
      lib',
    }:
    {
      os = "nixos";
      channel = "unstable";
      final = {
        lib = builtins.elem "x86_64-linux" lib.systems.flakeExposed;
        libP = {
          inherit (lib') top;
          common = lib'.common or null;
          node = lib'.node or null;
        };
      };
    };
}
