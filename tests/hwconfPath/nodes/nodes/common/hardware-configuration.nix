{ nodes, ... }:
{
  nixverse-test = {
    bar = nodes.current.x;
  };
}
