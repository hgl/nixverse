{
  nodes-0 =
    { nodes }:
    {
      os = "nixos";
      channel = "unstable";
      final = {
        x = 1;
        y = nodes.current.final.x + 1;
        current = nodes.current.final.x;
      };
    };
}
