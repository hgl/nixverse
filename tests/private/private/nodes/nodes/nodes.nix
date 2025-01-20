{
  nodes-0 =
    { nodes }:
    {
      final = {
        x = 2;
        y = nodes.current.final.x + 1;
        currentPrivate = nodes.current.final.x;
      };
    };
}
