{
  common =
    { nodes }:
    {
      os = "nixos";
      channel = "unstable";
      final = {
        x = 1;
        y = nodes.current.final.x + 1;
        currentCommon = nodes.current.final.x;
      };
    };
  nodesCommon-0 =
    { nodes }:
    {
      final = {
        x = 2;
        y = nodes.current.final.x + 1;
        currentNode = nodes.current.final.x;
      };
    };
}
