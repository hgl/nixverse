# Nixverse

Filesystem-based nix flake framework for multi-node configurations, cascading secrets management, parallel deployments, etc.

Once Nixverse is loaded in your flake, putting files in the correct location immediately allows you to use `nixos-rebuild switch` to activate a configuration. There is no need to import any file.

## Features

Nixverse is designed to manage all your nix configurations, so it’s uniquely positioned to offer a lot of features:

- Define nodes under `nixosConfigurations`/`darwinConfigurations` from files.
- Define nestable groups for nodes.
- Allow nodes to reference each other's configuration.
- Allow each node to select its own nixpkgs channel.
- Deploy multiple nodes in parallel.
- Install NixOS and nix-darwin with a single command.
- Define cascading secrets for groups and nodes.
- Import configurations and secrets from a private repo.
- Define custom lib functions, packages and modules.
- Define Home Manager configurations from files.
- And more.

## Real World Examples

The author's nix configurations (which obviously uses Nixverse) are available at [github.com/hgl/configs](https://github.com/hgl/configs).

## Quick Start

First, let's make your flake load Nixverse:

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

Let’s walk through some common tasks made easy with Nixverse.

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

Let's use the stable version of nixpkgs this time.

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

The `-nixos` suffix is required here because nixpkgs' stable channels are OS specific (e.g., `darwin` should use `nixpkgs-24.05-darwin`). Check out [the reference](./doc/reference.md#flake-inputs-naming-rules) on how the inputs are picked by a node.

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
  # Auto-generate the next line with `nixos-generate-config`
  nixpkgs.hostPlatform = "x86_64-linux";
  boot.loader.systemd-boot.enable = true;
  services.openssh.enable = true;
  # Add your own NixOS configuration
}
```

Notice in this case the two nodes share the same configuration. Nixverse also lets you detect what the current node is and what configurations other nodes use etc, allowing you to slightly adjust a node’s configuration. Refer to [the reference](./doc/reference.md#the-nodes-argument) on how it's done.

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

Incorporating Home Manager is usually quite involved, but Nixverse makes it a breeze:

First add a flake input to specify which version of the nixpkgs this Home Manager should use:

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

To make the user `foo` in node `hgl` managed by Home Manager, create this file:

```nix
# nodes/hgl/home/foo/home.nix
{ osConfig }:
{
  programs.git.enable = true;

  home.stateVersion = osConfig.system.stateVersion;
}
```

And you're done. Just activate this node, and the Home Manager configuration will be applied.

Nixverse also configures Home Manager for you according to best practices (e.g., setting `useGlobalPkgs` to `true`), so you can start writing Home Manager configuration right away.

## Directory Structure Overview

A typical Nixverse-managed flake looks like this:

```
your-flake/
├─ nodes/
│  ├─ your-node-name/
│  │  ├─ node.nix
│  │  ├─ configuration.nix
│  │  └─ home/
│  │     └─ your-user-name/
│  │        └─ home.nix
│  ├─ your-group-name/
│  │  ├─ group.nix
│  │  ├─ common/
│  │  │  ├─ configuration.nix
│  │  │  └─ home/
│  │  └─ your-subnode-name/
│  │     ├─ configuration.nix
│  │     └─ home/
├─ lib/
├─ pkgs/
├─ modules/
│  ├─ nixos/
│  ├─ darwin/
│  └─ home/
├─ private/ (replicates the structure of your-flake/)
│  ├─ secrets.yaml
│  ├─ nodes/
│  ├─ lib/
│  ├─ pkgs/
│  └─ modules/
├─ flake.nix
└─ flake.lock
```

- **nodes**: nodes and groups, one in each sub-directory
  - **node.nix**: defines the OS (e.g., NixOS or Darwin), nixpkgs channel, etc for a node
  - **group.nix**: similar to **node.nix**, defines sub-nodes en masse
  - **common**: common configurations for sub-nodes in a group
  - **configuration.nix**: NixOS or Darwin configuration
  - **home**: [Home Manager](https://github.com/nix-community/home-manager) users, one in each sub-directory
  - **home.nix**: Home Manager configuration
- **lib**: custom lib functions
- **pkgs**: custom packages
- **modules**: custom modules, each sub-directory corresponds to a specific type of modules
- **private**: git submodule for a private repo, for previously mentioned things you want to keep private
  - **secrets.yaml**: [sops](https://github.com/getsops/sops) secrets (using [sops-nix](https://github.com/Mic92/sops-nix)) for all nodes and groups

## Documentation

Read the [reference](./doc/reference.md) to learn more.

## License

MIT
