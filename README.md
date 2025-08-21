# Nixverse

Filesystem-based nix flake framework for multi-node configurations, cascading secrets management, parallel deployments, etc.

Nixverse eliminates 99% of your glue code by bringing Convention over Configuration to Nix — just like Rails did for web development. Simply place files in the right locations, and tools like `nixos-rebuild switch` will just work — no manual imports required.

Note: Nixverse is still alpha software. It may be full of holes and APIs may be changed without backward-compatibility. I'd love to have people give it a try, but please keep that in mind. :)

## Features

Nixverse is designed to manage all your nix configurations, so it’s uniquely positioned to offer a lot of features:

- Define nodes under `nixosConfigurations`/`darwinConfigurations` from files.
- Define nestable groups for nodes.
- Allow nodes to reference each other's configuration.
- Allow each node to select its own nixpkgs channel.
- Deploy multiple nodes in parallel.
- Define cascading and cross-referencing secrets for groups and nodes.
- Import configurations and secrets from a private repo.
- Define custom lib functions, packages and modules.
- Define Home Manager configurations from files.
- Install NixOS and nix-darwin with a single command.
- And more.

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
  outputs =
    inputs@{ nixverse, ... }:
    nixverse.lib.load {
      inherit inputs;
      flakePath = ./.;
    };
}
```

Now your directory structure becomes meaningful to Nix. (`flakePath = ./.` is necessary due to [a nix limitation](https://github.com/hercules-ci/flake-parts/issues/148).)

Let’s walk through some common tasks that Nixverse makes easier.

### Define and Deploy a Node

A node is simply a single machine, defined by creating a `node.nix` file under a `nodes/<hostName>` directory. The `<hostName>` will serve as a handle to refer to the machine and the machine’s host name (which can be overridden in its configuration).

Inside `node.nix`, specify the `os` (`nixos` or `darwin`) and the `channel` to use. The `os` decides determines whether the machine uses NixOS or [nix-darwin](https://github.com/nix-darwin/nix-darwin). The `channel` decides which flake inputs are made available to the node.

```nix
# nodes/hgl/node.nix
{
  os = "nixos";
  channel = "unstable";
}
```

Notice in `flake.nix` we used a flake input named `nixpkgs-unstable`. The `-unstable` suffix matches the node's `channel` and is how the node selects its nixpkgs version.

Next, create the NixOS configuration file `configuration.nix` under the node's directory:

```nix
# nodes/hgl/configuration.nix
{
  # You can auto-generate the system value with `nixos-generate-config`
  nixpkgs.hostPlatform = "x86_64-linux";
  boot.loader.systemd-boot.enable = true;
  services.openssh.enable = true;
  # Add your own NixOS configuration
}
```

That’s it! Now you can activate the configuration:

```bash
$ nixos-rebuild switch --flake '<path/to/flake>#hgl'
```

### Define and Deploy a Group of Nodes

To define a group of machines, create a `group.nix` file under a `nodes/<groupName>` directory.

```nix
# nodes/cluster/group.nix
{
  common = { lib, ... }: {
    os = lib.mkDefault "nixos";
    channel = lib.mkDefault "stable";
  };
  server1 = {};
  server2 = {
    channel = "unstable"
  };
  mac = {
    os = "darwin"
  };
}
```

This file must contain an attribute set, where each attribute represents a node (or a group) with the same format as `node.nix`. The `common` attribute is special — its content is shared across other nodes (or groups) in this group.

Notice the use of `lib.mkDefault`. The contents of `node.nix` and the attributes of `group.nix` are called meta configuration in Nixverse. These are actually special NixOS modules, so [the option priority rules](https://nixos.org/manual/nixos/stable/#sec-option-definitions-setting-priorities) apply. See [the reference for the available options](./doc/reference.md#meta-configuration).

Add the relevant flake inputs so nodes can use the nixpkgs channel they specify:

```diff
# flake.nix
{
  inputs = {
    nixpkgs-unstable.url = ...
+   nixpkgs-stable-nixos.url = "github:NixOS/nixpkgs/nixos-24.05";
+   nixpkgs-stable-darwin.url = "github:NixOS/nixpkgs/nixos-24.05-darwin";
    nixverse = ...
  };
  outputs = ...
}
```

The `-stable-nixos` and `-stable-darwin` suffixes are required. `stable` matches the node's `channel`, and `nixos`/`darwin` match the node's `os` values. The OS suffix is necessary because the stable nixpkgs channels are OS-specific.

We then define a common configuration for the three machine, and let `mac` override some of it:

```nix
# nodes/cluster/common/configuration.nix
{ pkgs, nodes, ...}: {
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  boot.loader.grub.enable = nodes.current.os != "darwin";
  services.openssh.enable = nodes.current.os != "darwin";

  environment.systemPackages = [ pkgs.rsync ];
}
```

```nix
# nodes/cluster/mac/configuration.nix
{
  nixpkgs.hostPlatform = "aarch64-darwin";
}
```

The `nodes` argument is powerful. it lets you access meta and actual configurations (using `nodes.<name>.config`) of any node or group. `nodes.current` refers to the current node. For example, from `server3`'s `configuration.nix`, you can access `server1`'s configuration via `nodes.server1.config.boot.loader.grub.enable`.

You can now activate the three servers:

```bash
# On server1
$ nixos-rebuild switch --flake <path/to/flake>#server1
# On server2
$ nixos-rebuild switch --flake <path/to/flake>#server2
# On server3
$ darwin-rebuild switch --flake <path/to/flake>#server2
```

There is a problem though. In order to activate them like this, you need to copy the flake directory to each server and activate them locally. Thankfully, Nixverse defines a default [flake app](https://nix.dev/manual/nix/2.18/command-ref/new-cli/nix3-run#apps) that allows not only remote deployment, but also in parallel. We just need to specify each server's address:

```diff
# nodes/cluster/group.nix
{
  common = { lib, ... }: {
    os = lib.mkDefault "nixos";
    channel = lib.mkDefault "stable";
  };
  server1 = {
+   deploy.targetHost = "10.0.0.1"
  };
  server2 = {
    channel = "unstable"
+   deploy.targetHost = "10.0.0.2"
  };
  mac = {
    os = "darwin"
  };
}
```

Now run

```
$ nix run . node deploy servers
```

Nixverse will use `nixos-rebuild` to deploy to `server1` and `server2` remotely and `darwin-rebuild` for `mac`, all in parallel.

### A Real-World Example

Let's end the Quick Start section with a more involved, real-world example — a simplified version of what I've done in [my own Nix configs](https://github.com/hgl/configs).

We’ll do the following:

1. Define two groups of machines: `servers` and `routers`.
1. Define their accepted SSH public keys at a central place.
1. Define secrets centrally and let each node safely use them.
1. Define a Home Manager user and have it use a custom module.
1. Install NixOS with this configuration to all machines in parallel.

You might expect these steps to take a long time, but as you’ll see, Nixverse can significantly speed up the process.

We first define the two groups:

```nix
# nodes/servers/group.nix
{
  common = {
    os = "nixos";
    channel = "unstable";
  };
  server1 = {};
  server2 = {};
}

# nodes/servers/common/configuration.nix
{
  boot.loader.grub.enable = true;
}
```

```nix
# nodes/routers/group.nix
{
  common = {
    os = "nixos";
    channel = "unstable";
  };
  router1 = {};
  router2 = {};
}

# nodes/routers/common/configuration.nix
{
  boot.loader.systemd-boot.enable = true;
  services.pppd = {
    enable = true;
    peers.wan.config = ''
      plugin pppoe.so
      name pppoe-username
    '';
  };
}
```

For simplicity, each node shares its group’s configuration.

We then add SSH access to all node by creating a `sshable` group that contains both the `servers` and `routers` groups:

```nix
# nodes/sshable/group.nix
{
  servers = {};
  routers = {};
}

# nodes/sshable/common/configuration.nix
{
  users.users.root = {
    # Your public ssh key that is accepted by all specified groups
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
}
```

We can of course define a NixOS module instead and have each group import it, but as the number of such nodes and groups increases, it can be difficult to track which nodes and groups have imported the module.

Each router needs both the PPPOE username and password to gain internet access, but we've so far refrained from directly specifying the password because everything in Nix is world-readable. We need a proper secrets solution.

There are many such solutions for Nix. You can use any one you like. Nixverse provides seamlessly (but optional) integration with [sops-nix](https://github.com/Mic92/sops-nix).

A few things need to exist before `sops-nix` can be used:

Create a master age key for `sops`:

```
age-keygen -o ~/.config/sops/age/keys.txt
```

Add the displayed public key to a `.sops.yaml` file in your flake root:

```yaml
creation_rules:
  - age: <your age public key>
```

That's all. It gives `sops` access to both the public and private keys.

Now we can specify the PPPOE password by running:

```
$ nix run . secrets edit
```

This will open a Nix file with your text editor. Change the content to:

```nix
{
  nodes = {
    routers = {
      pppoePassword = "mypassword";
    };
  };
}
```

Save and exit the editor and Nixverse will:

1. For each node eventually contains any secret, generate a SSH host key in its directory. In this case it's `router1` and `router2`.
1. Encrypt each node's secrets with the SSH host key, saved to `secrets.yaml` in the node's directory.
1. Import the `sops-nix` module and set `sops.defaultSopsFile = secrets.yaml`.
1. Encrypt the Nix file with the master age key, saved to `secrets.yaml` in the flake root.

At runtime, `sops-nix` will write the password to a file, which will be be loaded into `pppd`:

```diff
# nodes/routers/common/configuration.nix
{
  ...
  services.pppd = ...
+ environment.etc."ppp/pap-secrets" = {
+   mode = "0600";
+   text = "pppoe-username * @${config.sops.secrets.pppoePassword.path} *";
+ };
}
```

Add the `sops-nix` flake input:

```diff
# flake.nix
{
  inputs = {
    ...
    nixpkgs-stable-darwin.url = ...
+   sops-nix-unstable = {
+     url = "github:Mic92/sops-nix";
+     inputs.nixpkgs.follows = "nixpkgs-unstable";
+   };
    nixverse = ...
  };
  outputs = ...
}
```

And now the routers can establish PPPOE connections without the password being world-readable.

We now turn our eyes to per-user configuration. Home Manager is a popular module for that. It can configure software that NixOS doesn't provide options for. The Helix text editor is a good example. To use Home Manager in Nixverse, you simply create `users/<name>/home.nix` or `users/<name>/home/default.nix` in a node's (or a group's `common`) directory:

```nix
# nodes/servers/common/users/root/home.nix
{
  osConfig,
  ...
}:
{
  programs.helix = {
    enable = true;
    defaultEditor = true;
  };
  home.stateVersion = osConfig.system.stateVersion;
}
```

Again, add the Home Manager flake input:

```diff
# flake.nix
{
  inputs = {
    ...
    sops-nix-unstable = ...
+   home-manager-unstable = {
+     url = "github:nix-community/home-manager";
+     inputs.nixpkgs.follows = "nixpkgs-unstable";
+   };
    nixverse = ...
  };
  outputs = ...
}
```

That's it. Home Manager is now enabled for the root user, who uses Helix as the default editor.

There is one final improvement we can make. On servers, we want the shell prompt to show the host name, so we always know which machine we’re on. To do this, we’ll write a module and have the servers import it:

```nix
# modules/home/fish.nix
{
  programs.fish = {
    enable = true;
    functions = {
      fish_prompt = "printf '%s❯ ' (prompt_hostname)";
    };
  };
}
```

In this case a Home Manager module is created, you can easily create other types of modules at `modules/nixos`, `modules/darwin`, etc.

We could import this module directly using a relative path, but that quickly becomes painful. Instead, we’ll use the `modules'` argument that Nixverse provides to modules:

```diff
# nodes/servers/common/users/root/home.nix
{
  osConfig,
+ modules',
  ...
}:
{
+ imports = [ modules'.fish ];
  programs.helix = ...
  ...
}
```

Inside a Home Manager module, `modules'` contains all modules under `modules/home`. The same applies to `modules/nixos`, `modules/darwin`, etc.

We finally have a configuration we are happy with for all four nodes. But what if the machines are brand new and don’t have NixOS installed yet? How do you deploy to a machine that isn’t already running NixOS?

Fear not — Nixverse can install NixOS remotely and activate the configuration in one go. Under the hood, it uses [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) to do this.

In order to install NixOS, we need to tell Nixverse how to partition the hard drive. This is done by providing a `disk-config.nix` file in the node's directory (or group's `common` directory if all nodes share the same partition layout and the hard disks live at the same location) . This file is written using the [disko](https://github.com/nix-community/disko) module.

```nix
# nodes/servers/common/disk-config.nix
# nodes/routers/common/disk-config.nix
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda"; # Make sure it points to the correct disk
    content = {
      type = "gpt";
      partitions = {
        esp = {
          type = "EF00";
          size = "512M";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
```

And of course, don’t forget to add the `disko` flake input. (If you're wondering why we don't need to add the `nixos-anywhere` flake input. It's because it's simply a command line tool, which is included in Nixverse's own flake inputs):

```diff
{
  inputs = {
    ...
    home-manager-unstable = ...
+   disko-unstable = {
+     url = "github:nix-community/disko";
+     inputs.nixpkgs.follows = "nixpkgs-unstable";
+   };
    nixverse = ...
  };
  outputs = ...
}
```

We are finally done! To install NixOS on each machine, they need to first boot the official NixOS installer, i.e., the iso file. Once finished, we need to ssh into them as a root. To do that, one manual step is required. On each machine, either set a root password with `sudo passwd` or download your public ssh key and append it to `/root/.ssh/authorized_keys`.

As a final step, we need to tell Nixverse the address of each machine to install:

```diff
# nodes/servers/group.nix
{
  common = ...
  server1 = {
+   install.targetHost = "root@1.1.1.1";
  };
  server2 = {
+   install.targetHost = "root@2.2.2.2";
  };
}
```

```diff
# nodes/routers/group.nix
{
  common = ...
  router1 = {
+   install.targetHost = "root@3.3.3.3";
  };
  router2 = {
+   install.targetHost = "root@4.4.4.4";
  };
}
```

Notice we use `install.targetHost` this time. That address is for installing specifically, and `root` is also explicit specified.

Now we’re ready to install the configured NixOS to all machines in parallel.

```
$ nix run . node install servers routers
```

This command will partition each disk, transfer all required packages and the generated ssh host keys, and activate the full configuration — all in one shot.

And that’s it. Four freshly installed machines, fully configured, secrets encrypted, users provisioned, ready to rock and roll.

## Directory Structure Overview

A typical Nixverse-managed flake looks like this:

```
your-flake/
├─ nodes/
│  ├─ your-node-name/
│  │  ├─ node.nix
│  │  ├─ configuration.nix
│  │  └─ users/
│  │     └─ your-user-name/
│  │        └─ home.nix
│  ├─ your-group-name/
│  │  ├─ group.nix
│  │  ├─ common/
│  │  │  ├─ configuration.nix
│  │  │  └─ users/
│  │  └─ your-subnode-name/
│  │     ├─ configuration.nix
│  │     └─ users/
├─ lib/
├─ outputs/
├─ pkgs/
├─ modules/
│  ├─ nixos/
│  ├─ darwin/
│  ├─ flake/
│  └─ home/
├─ private/ (replicates the structure of your-flake/)
│  ├─ secrets.yaml
│  ├─ nodes/
│  ├─ lib/
│  ├─ outputs/
│  ├─ pkgs/
│  └─ modules/
├─ flake.nix
└─ flake.lock
```

- **nodes**: nodes and groups, one in each sub-directory
  - **node.nix**: defines the OS (e.g., NixOS or Darwin), nixpkgs channel, etc for a node
  - **group.nix**: similar to **node.nix**, defines sub-nodes en masse
  - **common**: common configurations for sub-nodes in a group
  - **configuration.nix**: NixOS or nix-darwin configuration
  - **home.nix**: [Home Manager](https://github.com/nix-community/home-manager) configuration
- **lib**: custom lib functions
- **outputs**: a [flake.parts module](https://github.com/hercules-ci/flake-parts), for specifying your flake outputs
- **pkgs**: custom packages
- **modules**: custom modules, each sub-directory corresponds to a specific type of modules
- **private**: git submodule for a private repo, for previously mentioned things you want to keep private
  - **secrets.yaml**: [sops](https://github.com/getsops/sops) secrets (using [sops-nix](https://github.com/Mic92/sops-nix))

## Reference

Read the [reference](./doc/reference.md) to learn more.
