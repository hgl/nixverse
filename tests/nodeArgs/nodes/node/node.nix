{
  inputs,
  common,
  nodes,
}:
{
  os = "nixos";
  channel = "unstable";
  final = {
    inputs = inputs.custom.value;
    common = common == { };
    nodes = {
      current = nodes.current.name;
    };
  };
}
