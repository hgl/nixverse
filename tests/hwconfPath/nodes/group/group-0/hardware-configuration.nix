{ nodes, ... }:
{
  nixverse-test = {
    bar2 = nodes.current.x;
  };
}
