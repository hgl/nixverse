{
  common =
    { lib' }:
    {
      os = "nixos";
      channel = "unstable";
      top = lib'.top;
      x = lib'.x;
      node = lib'.node;
    };
  nodelib-nodes-0 = { };
  nodelib-nodes-1 =
    { lib' }:
    {
      top = lib'.top + 1;
      x = lib'.x + 1;
      node = lib'.node + 1;
    };
}
