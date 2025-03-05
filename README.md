# Nixverse

File-based nix flake framework for multi-node configurations, cascading secrets management, parallel deployments, etc.

## Features

Nixverse is supposed to own all your nix configurations, so it's in a unique position to offer a lot of features:

- Define nodes under nixosConfigurations/darwinConfigurations from files.
- Define nestable groups for nodes.
- Allow nodes to reference each other's configuration.
- Allow each node to select its own nixpkgs channel.
- Deploy multiple nodes in parallel.
- Install NixOS and nix-darwin with a single command.
- Define cascading secrets for groups and nodes.
- Import configurations and secrets from a private repo.
- Define custom lib functions, packages and modules.
- Define home manager configurations from files.
- And more.

## Quick Start

Create `flake.nix` with the following content:

```nix
{
  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixverse = {
      url = "github:hgl/nixverse";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { self, nixverse, ... }: nixverse.load self {
    # Add your own flake outputs
  };
}
```

And then by creating these two files, a `nixosConfigurations.hgl` flake output is automatically defined:

```nix
# nodes/hgl/node.nix
{
  os = "nixos";
  channel = "unstable";
}
```

```nix
# nodes/hgl/configuration.nix
{
  boot.loader.systemd-boot.enable = true;
  services.openssh.enable = true;
  # Add your own NixOS configuration
}
```

Finally let's activate it:

```bash
$ nixos-rebuild switch --flake <path/to/flake>#hgl
```

Congratulations! You just created and activated a node with Nixverse.

## Documentation

[Reference](./doc/reference.md)

## License

MIT
