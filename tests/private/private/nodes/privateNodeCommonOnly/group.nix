{
  common =
    { nodes }:
    {
      os = "nixos";
      channel = "unstable";
      final = {
        x = 3;
        y = nodes.current.final.x + 1;
        currentCommon = nodes.current.final.x;
      };
    };
  overrideNodeCommonOnly-0 =
    { nodes }:
    {
      final = {
        x = 4;
        y = nodes.current.final.x + 1;
        currentNode = nodes.current.final.x;
      };
    };
}
