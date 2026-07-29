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
      # release-25.11 to match nixpkgs (stylix main tracks unstable and
      # references options like services.displayManager.generic that don't
      # exist in the 25.11 release).
      url = "github:nix-community/stylix/release-25.11";
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
        # stylix's module is imported here (not in the profile) because kata
        # does not thread `inputs` into node modules' specialArgs — a profile
        # that referenced `inputs.stylix…` in its `imports` would recurse. It is
        # inert unless a profile sets `stylix.enable` (nixos-gnome-desktop does).
        base = {
          nixos = [
            ./modules/node-mode.nix
            inputs.sops-nix.nixosModules.sops
            inputs.stylix.nixosModules.stylix
            # home-manager as a NixOS module, so profiles can set
            # `home-manager.users.<name>` (nixos-gnome-desktop does, for per-user
            # GNOME dconf). Sane fleet defaults; inert until a profile uses it.
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = lib.mkDefault true;
              home-manager.useUserPackages = lib.mkDefault true;
              home-manager.backupFileExtension = lib.mkDefault "hm-bak";
            }
          ];
          darwin = [ ./modules/node-mode.nix inputs.sops-nix.darwinModules.sops ];
        };
        # Node `profiles = [ "name" ]` entries resolve through the catalog.
        # Add behavior by IMPORTING vocabulary (blackmatter components, kata/iroha
        # letters) — never by hand-rolling behavior modules in this repo.
        profiles = profiles.table;
      };

      # ── THE INVOKER ──────────────────────────────────────────────────────
      # A fleet flake DECLARES `checks` (below) — but nothing in the fleet
      # workflow ever BUILDS them. `nixos-rebuild` / `darwin-rebuild` never
      # look at `checks`, and a fleet repo is private by default, so no CI
      # runs `nix flake check`. A declared-but-uninvoked check is not a weak
      # gate; it is nothing at all. So the gate goes where the rebuild cannot
      # route around it.
      #
      # kata's invariants are decided at EVAL time — iroha.mkEvalChecks
      # computes `passed` as a pure boolean, and the derivation only carries
      # that verdict. So force the verdict on the way into every SHIPPING
      # output: selecting `nixosConfigurations.<node>` forces `gate`, and a
      # red gate THROWS with every failing case named, before one byte is
      # built — on any host, with no CI, no builder, and no matching system.
      #
      # TIER: eval-rejected. Stronger than a CI gate (only-mitigated, and
      # vacuous in a private repo where Actions never run); weaker than
      # truly-unrepresentable — a Nix `throw` is not a compile error.
      suite = substrate.iroha.mkEvalChecks {
        name = "fleet-${fleet.config.name}";
        tests = fleet.invariants;
      };

      gate =
        let
          n = builtins.length (builtins.attrNames suite.tests);
          render =
            f:
            "  FAIL ${f.name}\n    expected: ${builtins.toJSON f.expected}\n    got:      ${builtins.toJSON f.result}";
        in
        # NON-EMPTY SUBJECT SET. A gate that runs over zero invariants is
        # green while proving nothing — the most extreme round-up available,
        # because the evidence looks like the strongest kind. Refuse it.
        if n == 0 then
          throw "fleet gate: the invariant suite is EMPTY — a gate over zero subjects proves nothing. Refusing to evaluate."
        else if !suite.passed then
          throw "fleet gate: FAILED — ${suite.summary} invariants\n${lib.concatStringsSep "\n" (map render suite.failures)}"
        else
          n;

      # Every shipping output passes through the gate. The DIAGNOSTIC outputs
      # (fleetReport / profileCatalog / checks) deliberately do not, so a
      # fleet whose gate is red can still be inspected to find out why.
      gated = v: builtins.seq gate v;
    in
    {
      nixosConfigurations = gated fleet.nixosConfigurations;
      darwinConfigurations = gated fleet.darwinConfigurations;

      # Typed deploy data (feed deploy-rs / colmena at your edge).
      fleetDeploy = gated fleet.deployRs;
      fleetRegistry = gated fleet.registry;

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

      # Still declared — this is what `nix flake check` builds, and what a
      # PUBLIC fleet repo should also gate in CI (see README "The gate").
      # It is the same verdict `gate` forces; it is not the mechanism that
      # makes the verdict unskippable.
      checks = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ] (
        system: fleet.checksFor (import nixpkgs { inherit system; })
      );

      # Makes the documented `nix flake init -t github:pleme-io/nix-template`
      # real — without this output that command fails with "template not found".
      templates.default = {
        path = ./.;
        description = "pleme-io kata-standard fleet repo — fill in fleet.nix, node hardware, secrets";
      };
    };
}
