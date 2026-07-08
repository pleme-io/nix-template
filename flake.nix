{
  description = "pleme-io/nix-template — a public, kata-standard fleet example over the pleme-io Nix vocabulary";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    substrate = {
      url = "github:pleme-io/substrate";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # stylix auto-themes GNOME/GDM/GTK/cursor/icons from one base16 palette;
    # consumed by profiles/nixos-gnome-desktop. Public upstream input.
    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # A real fleet adds the behavior vocabulary as inputs (all follow nixpkgs):
    #   blackmatter.url = "github:pleme-io/blackmatter";
    #   blackmatter-security.url = "github:pleme-io/blackmatter-security";
    #   ... then consume blackmatter.components.* in your profiles.
  };

  outputs =
    {
      self,
      nixpkgs,
      substrate,
      nix-darwin,
      ...
    }@inputs:
    let
      kata = substrate.kata;
      lib = nixpkgs.lib;

      # THE single profile catalog — name -> module, one interface (lib/profiles.nix).
      profiles = import ./lib/profiles.nix { inherit lib; };

      # THE BLANKS — every fleet-specific fact lives in fleet.nix (validated
      # against kata's strict schema; a typo fails eval with a named error).
      fleet = kata.mkFleet {
        config = import ./fleet.nix;
        inherit inputs;
        universes = {
          nixosSystem = nixpkgs.lib.nixosSystem;
          darwinSystem = nix-darwin.lib.darwinSystem;
        };
        # The typed-enum pattern (modules/node-mode.nix) is baked into every
        # node, so any node/profile can set `fleet.mode.shape` + read the facets.
        # sops-nix modules are in the base so the `secrets` blank (fleet.nix)
        # has a `sops.secrets` option to land on — without them a node with any
        # declared secret fails eval ("option sops does not exist").
        base = {
          nixos = [ ./modules/node-mode.nix inputs.sops-nix.nixosModules.sops ];
          darwin = [ ./modules/node-mode.nix inputs.sops-nix.darwinModules.sops ];
        };
        # Node `profiles = [ "name" ]` entries resolve through the catalog.
        # Add behavior by IMPORTING vocabulary (blackmatter components, kata/iroha
        # letters) — never by hand-rolling behavior modules in this repo.
        profiles = profiles.table;
      };
    in
    {
      inherit (fleet) nixosConfigurations darwinConfigurations;

      # Typed deploy data (feed deploy-rs / colmena at your edge).
      fleetDeploy = fleet.deployRs;
      fleetRegistry = fleet.registry;

      # Composed letters — derived for free from the one mkFleet call.
      # `fleetSshAliases` is shaped as blackmatter.components.ssh.extraHosts;
      # `fleetWireguard` is the per-node WireGuard projection (null unless you
      # declare `vpnLinks` in fleet.nix).
      fleetSshAliases = fleet.sshAliases;
      fleetWireguard = fleet.wireguard;

      # One typed query over the whole fleet:  nix eval .#fleetReport --json | jq
      fleetReport = fleet.report;

      # The profile catalog reflection:  nix eval .#profileCatalog --json | jq
      profileCatalog = profiles.catalog;

      checks = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ] (
        system: fleet.checksFor (import nixpkgs { inherit system; })
      );
    };
}
