{
  common =
    { lib' }:
    {
      os = "nixos";
      channel = "unstable";
      top = lib'.top;
    };
  toplib-nodes-0 = { };
  toplib-nodes-1 =
    { lib' }:
    {
      os = "nixos";
      channel = "unstable";
      top = lib'.top + 1;
    };
}
