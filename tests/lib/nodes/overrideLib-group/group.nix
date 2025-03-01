{
  overrideLib-node =
    { lib' }:
    {
      os = "nixos";
      channel = "unstable";
      final = {
        libP = {
          inherit (lib') override;
        };
      };
    };
}
