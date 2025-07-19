# Nixverse Reference

Table of Contents

1. [Installation](#installation)
   1. [From Scratch](#from-scratch)
   1. [Migrating from an Existing `flake.nix`](#migrating-from-an-existing-flakenix)
   1. [Entrypoint](#entrypoint)
   1. [Nixverse Options](#nixverse-options)
1. [Defining Nodes](#defining-nodes)
   1. [Node Meta Configuration](#node-meta-configuration)
   1. [The `nodes` Argument](#the-nodes-argument)
   1. [Special Node Meta Configuration Values](#special-node-meta-configuration-values)
   1. [`channel` and the `inputs` Argument](#channel-and-the-inputs-argument)
   1. [Flake Inputs Naming Rules](#flake-inputs-naming-rules)
   1. [The `pkgs-unstable` Argument](#the-pkgs-unstable-argument)
   1. [The `lib` and `lib'` Arguments](#the-lib-and-lib-arguments)
   1. [Auto-imported Node Files](#auto-imported-node-files)
1. [Defining Groups](#defining-groups)
   1. [Group Meta Configuration](#group-meta-configuration)
   1. [Special Group Meta Configuration Values](#special-group-meta-configuration-values)
1. [Defining Custom Lib Functions](#defining-custom-lib-functions)
1. [Defining Custom Packages](#defining-custom-packages)
1. [Defining Custom Modules](#defining-custom-modules)
1. [Defining Home Manager Configurations](#defining-home-manager-configurations)
1. [Secrets Management](#secrets-management)
   1. [Sops Secrets and Cascading](#sops-secrets-and-cascading)
   1. [Encrypting and Decrypting Files](#encrypting-and-decrypting-files)
   1. [Generating Secret Files with `Makefile`](#generating-secret-files-with-makefile)
1. [Private Configurations and Secrets](#private-configurations-and-secrets)
1. [The `nixverse` Command Line Tool](#the-nixverse-command-line-tool)
   1. [Install the `nixverse` Command Line Tool](#install-the-nixverse-command-line-tool)
   1. [Deploy Multiple Nodes in Parallel](#deploy-multiple-nodes-in-parallel)
   1. [Install NixOS and nix-darwin](#install-nixos-and-nix-darwin)

## Installation

### From Scratch

To create a new Nixverse project from scratch, execute the following commands, replacing `<flakeDir>` with your desired path:

```bash
$ mkdir -p <flakeDir>
$ cd <flakeDir>
$ nix flake init -t github:hgl/nixverse
```

### Migrating from an Existing `flake.nix`

To integrate Nixverse into an existing `flake.nix`, update it as follows:

```nix
{
  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Add your other flake inputs here
    nixverse = {
      url = "github:hgl/nixverse";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };
  outputs = { self, nixverse, ... }: nixverse.load self {
    # Include your custom flake outputs here
  };
}
```

Ensure other flake inputs are renamed appropriately to follow Nixverse's naming conventions (see [Flake Inputs Naming Rules](#flake-inputs-naming-rules)). Refer to [Defining Nodes](#defining-nodes) for details on how inputs are utilized by nodes.

### Entrypoint

The `nixverse.load` function serves as the entrypoint for Nixverse. It requires two arguments:

1. `self`: The reference to your flake's final outputs, passed from the outputs attribute.
2. **Custom Flake Outputs**: An attribute set containing your custom flake outputs.

### Nixverse Options

The `nixverse` output can be specified to configurate Nixverse. It's an attribute set that defines the following options:

- `inheritLib`
  - Determines whether the `lib'` argument (see [Defining Custom Lib Functions](#defining-custom-lib-functions)) also contains functions from input `nixverse.lib`.
  - **Type**: boolean
  - **Default**: `true`

## Defining Nodes

A node corresponds to an entry in the flake outputs `nixosConfigurations` or `darwinConfigurations`.

Two files are required to define a node:

- `node.nix`: contains the node's meta configuration.
- `configuration.nix`: contains the standard NixOS or nix-darwin configuration.

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
  users.mutableUsers = false;
  services.openssh.enable = true;
}
```

This defines `nixosConfigurations.hgl` in the flake outputs.

From here on, configuration in `node.nix` (or `group.nix`, see [Defining Groups](#defining-groups)) are called "meta configuration", while those in `configuration.nix` (and its imports) are simply "configurations".

For more on configuration options, consult the [NixOS configuration options](https://nixos.org/manual/nixos/unstable/options), or [nix-darwin configuration options](https://daiderd.com/nix-darwin/manual/index.html).

## Node Meta Configuration

A node's meta configuration is an attribute set or a function that returns an attribute set.

### The `nodes` Argument

A node's meta configuration can be accessed in both `node.nix` and its configuration files from the `nodes` argument:

```nix
# nodes/hgl/node.nix
{ nodes }: {
  os = "nixos";
  channel = "unstable";
  dhcpRange = {
    start = 100;
    end = nodes.current.dhcpRange.start + 150;
  };
}
```

```nix
# nodes/hgl/configuration.nix
{ nodes, ... }: {
  services.dnsmasq.settings =
    let inhert (nodes.current.dhcpRange) start end; in
    {
      dhcp-range = "192.168.1.${start},192.168.1.${end}"
    };
}
```

- Use `nodes.current` to refer to the current node's meta configuration.
- Use `nodes.<name>` (e.g., `nodes.hgl`) to refer to another node's meta configuration.

Typically, define authoritative values in `configuration.nix`. Other nodes can access these via `nodes.<name>.config` (see below for explanation on `config`.) Only put a value in the meta configuration when it presents the configurable data in a much cleaner way.

### Special Node Meta Configuration Values

There are a few special meta configuration values:

Required:

- `os`
  - Define the node under `nixosConfigurations` or `darwinConfigurations`.
  - Type: one of `"nixos"`, `"darwin"`,
- `channel`
  - Use the flake inputs with the corresponding channel value.
  - Type: string

Read Only:

- `name`
  - The node's name.
  - **Type**: string
- `type`
  - **Type**: `"node"`
- `config`
  - The node's resolved NixOS or nix-darwin configuration value.
  - **Type**: attribute set
- `parentGroups`
  - The node's parent group names.
  - **Type**: list of strings
- `groups`
  - The node's ancestor group names.
  - **Type**: list of strings

Optional

- `deploy.targetHost`
  - Deploy this node to the specified host when running `nixverse node deploy`. Leave empty to deploy locally.
  - **Type**: string
  - **Example**: `root@nixos`
- `deploy.buildOnRemote`
  - Build the configuration on the host at `deploy.targetHost`.
  - **Type**: boolean
  - **Default**: `false`
- `deploy.useRemoteSudo`
  - Prefix remote commands that run on `deploy.targetHost` with `sudo`, allowing deploying as non-root user.
  - **Type**: boolean
  - **Default**: `false`
- `deploy.sshOpts`
  - Set ssh options for connection to `deploy.targetHost`.
  - **Type**: list of strings
  - **Default**: `[]`
  - **Example**: `[ "StrictHostKeyChecking=no" ]`
- `install.targetHost`
  - Install NixOS to this node when running `nixverse node install`.
  - **Type**: string
  - **Default**: `config.deploy.targetHost`
- `install.buildOnRemote`
  - Build the configuration on the host at `install.targetHost`.
  - **Type**: boolean
  - **Default**: `config.deploy.buildOnRemote`
- `install.sshOpts`
  - Set ssh options for connection to `install.targetHost`.
  - **Type**: list of strings
  - **Default**: `config.deploy.sshOpts`
  - **Example**: `[ "StrictHostKeyChecking=no" ]`

### `channel` and the `inputs` Argument

The `channel` meta configuration determines which flake inputs are available to a node, via the `inputs` argument:

```nix
# flake.nix
{
  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable-nixos.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-stable-darwin.url = "github:NixOS/nixpkgs/nixpkgs-24.05-darwin";
    nixvim-unstable = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nixvim-stable-nixos = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs-stable-nixos";
    };
    nixvim-stable-darwin = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs-stable-darwin";
    };
  }
}
```

```nix
# nodes/linux-server/node.nix
{ inputs }: {
  os = "nixos";
  channel = "stable";
  vlanIds = inputs.nixpkgs-unstable.lib.range 2 10
}
# nodes/linux-server/configuration.nix
{ inputs, ... }: {
  # uses nixvim-stable-nixos
  imports = [ inputs.nixvim.nixosModules.nixvim ]
}
```

```nix
# nodes/linux-desktop/node.nix
{
  os = "nixos";
  channel = "unstable";
}
# nodes/linux-desktop/configuration.nix
{ inputs, ... }: {
  # uses nixvim-unstable
  imports = [ inputs.nixvim.nixosModules.nixvim ]
}
```

```nix
# nodes/mac/node.nix
{
  os = "darwin";
  channel = "stable";
}
# nodes/mac/configuration.nix
{ inputs, ... }: {
  # uses nixvim-stable-darwin
  imports = [ inputs.nixvim.nixDarwinModules.nixvim ]
}
```

### Flake Inputs Naming Rules

Flake inputs are filtered and renamed for each node. The following rules apply:

1. An input's name is of the pattern `<project>[-<channel>][-<os>]`.
1. `<os>` must be dropped when `<channel>` is `any`, and is other optional. When it exists, it's either `nixos` or `darwin`.
1. `<channel>` can be any value.
1. An input is only available to a node, as `inputs.<project>`, if (both must be satisfied)
   1. its `<channel>` is `any` or is the same as the node's meta configuration `channel`
   1. its `<os>` is omitted or is the same as the node's meta configuration `os`.
1. If an input `<project>-unstable` exists, and a node's meta configuration `channel` is not `"unstable"`, it's avaliable to the node as `inputs.<project>-unstable`. This allows a stable node to also use unstable packages for example.
1. If both `<channel>` are `<os>` omitted (make sure `<project>` doesn't accidentally apply the previous rules), the input is not available to any nodes, and is only usable in `flake.nix`. This should generally be avoided and is only useful for the `nixverse` input.

Examples:

| Flake Input            | node's `os` | node's `channel` | name in `inputs` |
| ---------------------- | ----------- | ---------------- | ---------------- |
| nixvim-unstable        | `"darwin"`  | `"unstable"`     | nixvim           |
| nixvim-unstable        | `"nixos"`   | `"foo"`          | nixvim-unstable  |
| nixvim-unstable-darwin | `"nixos"`   | `"unstable"`     | _not available_  |
| nixvim-unstable-nixos  | `"nixos"`   | `"unstable"`     | nixvim           |
| nixvim-foo-nixos       | `"nixos"`   | `"foo"`          | nixvim           |
| nixvim-foo             | `"darwin"`  | `"foo"`          | nixvim           |
| nixvim-any             | `"nixos"`   | `"foo"`          | nixvim           |
| nixvim                 | `"darwin"`  | `"foo"`          | _not available_  |

### The `pkgs-unstable` Argument

As a shortcut, if an input named `nixpkgs-unstable` or `nixpkgs-unstable-<os>` exists, and a node's `channel` is not `"unstable"`, it's configuration files are provided with a `pkgs-unstable` argument, which contains packages from nixpkgs' unstable channel.

### The `lib` and `lib'` Arguments

`node.nix` also has access to a `lib` argument, which the same as the one in its configuration files: the `lib` attribute from the corresponding `nixpkgs` input.

In addition, it also has access to a `lib'` argument, which is explained in [Defining Custom lib Functions](#defining-custom-lib-functions).

### Auto-imported Node Files

A few files inside the node folder (e.g., `nodes/hgl`) will be imported automatically:

- `hardware-configuration.nix`: generated automatically when running `nixverse node install`, or can be generated with `nixos-generate-config`.
- `disk-config.nix`: refer to the section on [installing NixOS and nix-darwin](#install-nixos-and-nix-darwin).

## Defining Groups

A group does not directly define an entry in the flake output `nixosConfigurations` or `darwinConfigurations`, but can define multiple nodes at once or contain other groups using a `group.nix` file and associated `configuration.nix` files.

```nix
# nodes/web-servers/group.nix
{
  common = {
    os = "nixos";
    channel = "stable";
    domain = "example.com"
  };
  web-server1 = { nodes }: {
    fqdn = "${nodes.current.name}.${nodes.current.domain}"
  };
  web-server2 = { nodes }: {
    fqdn = "${nodes.current.name}.${nodes.current.domain}"
  };
}
```

```nix
# nodes/web-servers/web-server1/configuration.nix
{
  users.mutableUsers = false;
  services.openssh.enable = true;
}
```

```nix
# nodes/web-servers/web-server2/configuration.nix
{
  users.mutableUsers = false;
  services.openssh.enable = true;
}
```

Two flake outputs `nixosConfigurations.web-server1` and `nixosConfigurations.web-server1` are then automatically defined.

## Group Meta Configuration

A `group.nix` file must contain an attribute set where

- Each key is a node or group name.
- Each values is an attribute set or a function returning an attribute set.
- The `common` key defines shared, overridable meta configurations for these nodes or groups.

The `common` meta configuration accepts two arguments:

- `common`: the `common` meta configuration itself.
- `nodes`: meta configurations from all nodes/groups.

All other meta configurations accepts the `nodes` arguments.

With these arguments, the previous example can actually be simplified:

```nix
# nodes/web-servers/group.nix
{
  common = { common, nodes }: {
    os = "nixos";
    channel = "stable";
    domain = "example.com";
    fqdn = "${nodes.current.name}.${common.domain}";
  };
  web-server1 = {};
  web-server2 = {};
}
```

For each key that is not `"common"`, if a node or group is already defined by a `node.nix` or `group.nix` file, it means that this group contains the node or group. Otherwise, it defines a new node. Such a node can be defined by multiple parent groups. Its final meta configuration comes from deeply merging each parent's corresponding meta configuration, in parent names' lexical order (e.g., node meta configuration of `parentB` overrides that of `parentA`).

```nix
# nodes/servers-a/group.nix
{
  server = {
    x = "a"
  };
}
```

```nix
# nodes/servers-b/group.nix
{
  server = {
    x = "b"
  };
}
```

```nix
# nodes/servers-a/server/configuration.nix
{ nodes, ... }: {
  # nodes.current.x equals to "b"
}
```

A node can be contained by multiple layers of groups (ancestors), and its final meta configuration is a result of merging the meta configurations from all ancestor groups deeply, in the following order:

```
grandparent < parentB < parentA < node itself
```

Where `<` means "whose corresponding meta configuration gets overridden by".

```nix
# nodes/servers/group.nix
{
  web-servers = {
    x = "grandparent"
  };
}
```

```nix
# nodes/web-servers/group.nix
{
  web-server1 = {
    x = "parent"
  };
}
```

```nix
# nodes/web-server1/node.nix
{
  x = "self";
}
```

```nix
# nodes/web-server1/configuration.nix
{ nodes, ... }: {
  # nodes.current.x equals to "self"
}
```

### Special Group Meta Configuration Values

Read Only:

- `name`
  - The group's name.
  - **Type**: string
- `type`
  - **Type**: `"group"`
- `children`
  - The group's child node or group names.
  - **Type**: list of strings
- `childNodes`
  - The group's child node names.
  - **Type**: list of strings
- `nodes`
  - The group's descendant node names.
  - **Type**: list of strings
- `parentGroups`
  - The group's parent group names.
  - **Type**: list of strings
- `groups`
  - The group's ancestor group names.
  - **Type**: list of strings

### Auto-imported Group Files

The `configuration.nix` file and all [auto-imported node files](#auto-imported-node-files) can also be created for a group, and will be imported by the corresponding node(s). Specifically:

- Files in `nodes/<group>/common` are imported by all descendant nodes.
- Files in `nodes/<group>/<node>` are imported by the child node.
- Files in `nodes/<group>/<subgroup>` are imported by all descendant nodes of the subgroup.

The previous example configuration for web servers can be simplified as:

```nix
# nodes/web-servers/common/configuration.nix
{
  users.mutableUsers = false;
  services.openssh.enable = true;
}
```

## Defining Custom Lib Functions

You can create a `lib.nix` or `lib/default.nix` file at various places that contains an attribute set or a function returning an attribute set, and their deeply merged value can be accessed in `node.nix`, `group.nix` or configuration files from the `lib'` argument.

Files under `nodes/<node>`, `nodes/<group>/common` or `nodes/<group>/<node>` have access to lib functions defined from

- The flake directory.
- The node's parent and ancestor groups' `common` directories.
- The node's own directory.

With latter ones overriding preceding ones.

If the file contains a function, the following arguments are available:

- `lib`: `nixpkgs`' lib functions. Which `nixpkgs` input gets used is determined by the node accessing the `lib'` argument.
- `lib'`: the custom lib itself. Only its own lib functions and those defined in parent directories are available.
- `inputs`: same as the node's `inputs` argument. The input names are determined by the node accessing the `lib'` argument.

The `lib'` argument in the flake directory's lib file by default refer to itself, but if the `inheritLib` [Nixverse option](#nixverse-options) is `true`, it also contains [Nixverse's lib functions](../lib/default.nix).

Examples:

```nix
# lib.nix
{
  plusOne = a: a + 1;
}
# nodes/hgl/lib.nix
{ lib' }: {
  plusTwo = a: (lib'.plusOne a) + 1;
}
```

```nix
# nodes/hgl/configuration.nix
{ lib', ... }: {
  # lib'.plusTwo 1 equals 3 here
}
```

## Defining Custom Packages

Custom packages, available to configuration files from the `pkgs'` argument, are defined in the `pkgs/<name>.nix` or `pkgs/<name>/default.nix` file. Each file should be a function that returns a nix derivation.

You can specify the dependent package names as the function's arguments, plus:

- `pkgs-unstable`: exists only if the node accessing the `pkgs'` argument uses a channel not equal to `"unstable"` and a `nixpkgs-unstable` input exists. It provides unstable nixpkgs packages.
- `pkgs'`: contains custom packages.
- [Nixverse's packages](../pkgs)

```nix
# pkgs/greet.nix
{
  writeShellScriptBin,
}:
writeShellScriptBin "greet" ''
  echo hi
''
```

```nix
# nodes/hgl/configuration.nix
{ pkgs', ... }: {
  environment.systemPackages = [ pkgs'.greet ];
  # "greet" command will be available in your $PATH
}
```

In your flake.nix, these packages can be accessed by calling the `nixverse.loadPkgs'` function. It requires two arguments:

1. `self`: The reference to your flake's final outputs, passed from the outputs attribute.
2. An attribute set containing:
3. `nixpkgs`: the `nixpkgs` input
4. `system`:

For example:

```nix
{
  inputs = {
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Add your other flake inputs here
    nixverse = {
      url = "github:hgl/nixverse";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };
  outputs = { self, nixpkgs-unstable, nixverse, ... }: nixverse.load self {
    packages = nixverse.lib.forAllSystems (system: {
      inherit (nixverse.loadPkgs' self {
        nixpkgs = nixpkgs-unstable;
        inherit system;
      }) foo bar;
    })
  };
}
```

This exposes the foo and bar packages through the `packages` output, with their dependencies tracking the `nixpkgs-unstable` input.

## Defining Custom Modules

Custom modules, available to configuration files from the `modules'` argument, are defined in the `modules/<type>/<name>.nix` or `modules/<type>/<name>/default.nix` file, where `<type>` is one of `"nixos"`, `"darwin"`. They are made available to a node if the node's `os` meta configuration equals their `<type>`.

Custom home manager modules, available to home configuration files (explained later) from the `modules'` argument, are defined in the `modules/home/<name>.nix` or `modules/home/<name>/default.nix` file.

```nix
# modules/nixos/my-nixvim.nix
{
  programs.nixvim = {
    enable = true;

    colorschemes.catppuccin.enable = true;
    plugins.lualine.enable = true;
  };
}
```

```nix
# nodes/hgl/configuration.nix
{ modules', ... }: {
  imports = [ modules'.my-nixvim ];
}
```

## Defining Home Manager Configurations

A home manager configuration can be defined by these files:

- `nodes/<node>/home/<user>/home.nix`: contains the home manager configuration for `<user>`, available to `<node>`.
- `nodes/<group>/common/home/<user>/home.nix`: contains the home manager configuration for `<user>`, available to all `<group>`'s descendant nodes.
- `nodes/<group>/<node>/home/<user>/home.nix`: contains the home manager configuration for `<user>`, available toy `<node>`.

The above files can co-exist, and they are all auto-imported. Nixverse will also import the home manager module and configurate it appropriately. When one of these files exists, make sure the a `home-manager` flake input (after renaming) exist.

The arguments `nodes`, `inputs` and `pkgs'` are available to the home manager configuration too. And the `modules'` argument contains the modules defined in `modules/home` (see above).

## Secrets Management

You are free to use any nix secret solutions, but Nixverse provides some automation for [sops-nix](https://github.com/Mic92/sops-nix). It's chosen over others because it enables easy implementation of secret cascading and it also supports embedding secrets in files.

### Sops Secrets and Cascading

To use sops-nix with Nixverse, you need to create a `.sops.yaml` file in the flake directory:

```yaml
# .sops.yaml
creation_rules:
  - age: <age public key>
```

Where `<age public key>` corresponds to a private key in your `keys.txt` file (read the [sops manual](https://github.com/getsops/sops/blob/main/README.rst) on how to create the `keys.txt` file and where it lives.).

Run `nixverse secrets edit`, a `secrets.yaml` file in the flake directory will be open in your text editor. This file contains all secrets for all nodes and groups. It contains an object with node and group names as the keys, each has sops secrets as values.

After you save the file and exit your editor, the `secrets.yaml` file will be encrypted with your age public key, and for each listed node, these files will be created automatically in its directory:

- `secrets.yaml`: this file only contains the secrets nesting under the node and its ancestor groups, deeply merged and encrypted. The merging order is the same as the meta configuration. It's encrypted with the node's public ssh host key.
- The node's public and private ed25519 ssh host key: the private key will be encrypted with your age public key, and the unencrypted private key is saved to the corrensponding node directory in the flake directory's `build` directory, which should be ignored by git. The unencrypted private key will be automatically generated from the encrypted private key if it's missing. You should commit the public key and the encrypted private key.

```yaml
# opened secrets.yaml
database:
  dbPassword: mypassword
web-server:
  acmeDnsCredential: xxxxx
```

```nix
# nodes/web-server/configuration.nix
{
  sops.secrets = {
    acmeDnsCredential = { };
  };
  security.acme.certs."example.com" = {
    dnsProvider = "cloudflare";
    credentialFiles = {
      CF_DNS_API_TOKEN_FILE = config.sops.secrets.acmeDnsCredential.path;
    };
  };
}
```

`nixverse secrets edit` also takes a yaml file path as an argument. If the file lives in a node directory, it's decrypted with node's private ssh host key, otherwise it's decrypted with your age private key.

### Encrypting and Decrypting Files

You can use `nixverse secrets encrypt` and `nixverse secrets decrypt` to encrypt/decrypt a file. If the file lives in a node directory, it's encrypted/decrypted with node's ssh public/private host key, otherwise it's encrypted/decrypted with your age public/private key. The node's ssh host keys will be generate automatically if they don't exist.

When you use `nixverse node deploy` and `nixverse node install` to deploy/install nodes, the corresponding ssh host keys will automatically be copied to each node.

If a node's directory contains the `secrets.yaml` file, the `sops-nix` module will be automatically imported, with the `sops.defaultSopsFile` configuration pointing to it.

### Generating Secret Files with `Makefile`

You can probably generate any file you need with nix configuration directly, except for secrets. They have to be generated outside nix. A popular tool that can facilitate is that [GNU Make](https://www.gnu.org/software/make/).

Nixverse internally uses GNU Make to generate node ssh host keys.

If there is a `Makefile` in your flake directory, `nixverse node deploy` and `nixverse node install` will invoke it with `make` as part of the process, using non-group node names prefixed `nodes/` as the targets.

When it calls your `Makefile`, a few things will be defined:

- Each non-group node's name, prefixed with `nodes/`, is a phony target (e.g., `.PHONY: nodes/hgl`).
- For each non-group node, `node_<name>_os`, `node_<name>_channel` are defined, with `<name>` being the node name.
- For each group, `<name>_node_names` is defined, with `<name>` being the group name. It contains the group's all descendant node names, separated with spaces.

When generating a secret, prefer generating the encrypted file in the `private` submodule, and then generate the cleartext file from it in the `build` directory. For a node secret file, generate the cleartext file in `build/nodes/<name>`, with `<name>` being the node name.

Here is an example `Makefile` to illustrate the previous points:

```Makefile
# Specify the files to generate when a group is deployed
$(foreach node_name,$(servers_node_names),$(eval \
  nodes/$(node_name): private/nodes/servers/$(node_name)/ipsec-server.key
))

private/nodes/servers/%/ipsec-server.key: | private/nodes/servers/%
	openssl ecparam -genkey \
		-name prime256v1 \
		-noout \
		-out $@
	nixverse secrets encrypt $< $@
build/nodes/servers/%/ipsec-server.key: private/nodes/servers/%/ipsec-server.key | build/nodes/servers/%
	nixverse secrets decrypt $< $@

$(foreach node_name,$(servers_node_names),$(eval \
  private/nodes/servers/$(node_name) \
  build/nodes/servers/$(node_name) \
)):
	mkdir -p $@
```

## Private Configurations and Secrets

There are some configuration values that you probably don't want to expose to the world. For example, you network card's MAC address, your server's public IP address, etc. And even though your secrets are encrypted, you probably don't want to expose them either.

Nixverse allows you to put all these private info in a private git repo, and then references it as a submodule at the `private` directory in the flake directory.

The content of the submodule should replicate that of the outer flake directory thus allowing you to create private node/group configuration, packages, modules, `Makefile` etc. They will be deeply merged with the corresponding public ones with the privat ones overriding the public ones.

Notice you can still refer to a private node configuration value, package or module etc from the public configuration, and the value will be used at the runtime. It's just the value or the content will not be visible to people who only has access to your public flake repo.

```nix
# nodes/hgl/configuration.nix
{ nodes, ...}: {
  networking.interfaces.lan.macAddress = nodes.current.lanMacAddress;
}
# private/nodes/hgl/node.nix
{
  lanMacAddress = "00:11:22:33:44:55";
}
```

`secrets.yaml` files and node ssh host keys, by default will be generated in the flake directory. But if the private directory exists, they will be generated inside it instead.

## The `nixverse` Command Line Tool

The Nixverse CLI provides parallel deployments, secret management and NixOS and nix-darwin installation.

Run `nixverse help` to learn about its usage.

### Install the `nixverse` Command Line Tool

The `pkgs'` argument for configurations contains a `nixverse` package. You can put it in configuration `environment.systemPackages` or home manager configuration `home.packages` to make it available on the command line.

### Deploy Multiple Nodes in Parallel

After you have specified the `deploy` meta configuration for the nodes you want to deploy with remote deployment values. You can run `nixverse nodes deploy <name>...`, where ` <name>...` can be one or more node or group names, and the result descendant nodes will be deployed in parallel.

### Install NixOS and nix-darwin

The Nixverse CLI allows NixOS to be installed declaratively to a remote machine. Simply follow these steps:

1. Create a `disk-config.nix` file for your node. It contains [disko](https://github.com/nix-community/disko) options to partition the disk.
1. Boot the NixOS ISO image on the remote machine and make it accessible with SSH.
1. Specify the [`install` meta configuration](#special-node-meta-configuration-values) for your node. Set its SSH address to `install.targetHost` (or `deploy.targetHost`).
1. Run `nixverse nodes install <name>...`. If ` <name>...` contains more than one node, all of them will be installed in parallel. (This command simply invokes [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)).

For a Darwin node, running `nixverse nodes deploy` installs `nix-darwin` automatically. Make sure Nix itself is installed first and the meta configuration `deploy.local` is set to `true`.
