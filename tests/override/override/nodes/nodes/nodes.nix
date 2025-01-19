{
  nodes-0 =
    { nodes }:
    {
      final = {
        x = 2;
        y = nodes.current.final.x + 1;
        currentOverride = nodes.current.final.x;
      };
    };
}
