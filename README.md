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

## Real World Examples

The author's nix configurations (which obviously uses Nixverse) is avaliable at [github.com/hgl/configs](https://github.com/hgl/configs).

## Quick Start

First, let's get nixverse loaded in your flake:

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

And let's see how some common tasks can be easily achieved with Nixverse.

### Define and Deploy a Node

Create these two files, and `hgl` will be automatically defined under the `nixosConfigurations` flake output:

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
  # You can have this auto-generated with `nixos-generate-config`
  nixpkgs.hostPlatform = "x86_64-linux";
  boot.loader.systemd-boot.enable = true;
  services.openssh.enable = true;
  # Add your own NixOS configuration
}
```

Then it can be directly activated:

```bash
$ nixos-rebuild switch --flake <path/to/flake>#hgl
```

### Define and Deploy a Group of Nodes

Let's used the stable version of nixpkgs this time.

First add a flake input for it:

```diff
{
  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
+   nixpkgs-stable-nixos.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixverse = {
      url = "github:hgl/nixverse";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };
}
```

The `-nixos` suffixed is required here because each operating system uses a different stable version of nixpkgs (e.g., `darwin` uses `nixpkgs-24.05-darwin`). Check out [the reference](./doc/reference.md#flake-inputs-naming-rules) on how the inputs are picked by a node.

Create these two files, and both `server1` and `server2` will be automatically defined under the `nixosConfigurations` flake output:

```nix
# nodes/servers/group.nix
{
  common = {
    os = "nixos";
    channel = "stable";
  };
  server1 = {};
  server2 = {};
}
```

```nix
# nodes/servers/common/configuration.nix
{
  # You can have this auto-generated with `nixos-generate-config`
  nixpkgs.hostPlatform = "x86_64-linux";
  boot.loader.systemd-boot.enable = true;
  services.openssh.enable = true;
  # Add your own NixOS configuration
}
```

Notice in this case the two nodes share the same configuration. Nixverse also lets you detect what the current node is and what configurations other nodes use etc, to configurate a node slightly differently. Refer to [the reference](./doc/reference.md#the-nodes-argument) on how it's done.

They can be individually activated:

```bash
$ nixos-rebuild switch --flake <path/to/flake>#server1
$ nixos-rebuild switch --flake <path/to/flake>#server2
```

Or you can use Nixverse's CLI to deploy all nodes in the group in parallel:

```bash
$ cd <path/to/flake>
$ nix run github:hgl/nixverse node deploy servers
```

### Define Home Manager Configuration for a User

Incorporating home manager is usually quite involved, but Nixverse makes it a breeze:

First add a flake input to specify which version of the nixpkgs this home manager should use:

```diff
{
  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable-nixos.url = "github:NixOS/nixpkgs/nixos-24.05";
+   home-manager-unstable = {
+     url = "github:nix-community/home-manager";
+     inputs.nixpkgs.follows = "nixpkgs-unstable";
+   };
    nixverse = {
      url = "github:hgl/nixverse";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };
}
```

Create a single file, and the user `foo` will automatically be under home manager's management:

```nix
# nodes/hgl/home/foo/home.nix
{ osConfig }:
{
  programs.git.enable = true;

  home.stateVersion = osConfig.system.stateVersion;
}
```

Nixverse configurates home manager for you according to best practices (e.g., setting `useGlobalPkgs` to `true`), so you can start writing home manager configuration right away.

Thank you for reading through to the end of Quick Start. Nixverse can provide a lot more convenience like these, be sure to check out the reference to learn about them.

## Documents

[Reference](./doc/reference.md)

## License

MIT
