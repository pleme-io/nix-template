# fleet.nix — THE BLANKS.
#
# This file is the ENTIRE fleet-specific surface (plus per-node hardware files
# under nodes/ and your SOPS-encrypted secrets.yaml). It is validated against
# kata's strict typed schema (substrate/lib/kata/fleet-config.nix) — unknown
# keys and type errors fail evaluation with a NAMED error.
#
# Everything BEHAVIORAL comes from the vocabulary:
#   fleet.nix (you) -> kata (fleet shape) -> iroha (composition alphabet)
#                   -> blackmatter (components) -> nixpkgs module system
# If you find yourself writing a behavior module in THIS repo, stop — extend the
# vocabulary instead (see docs/PATTERNS.md).
#
# Everything below is EXAMPLE data. Replace it with your fleet's facts.
{
  name = "example-fleet";

  # ── DNS / reachability ────────────────────────────────────────────────
  # Hostnames resolve as <host>.<location>.<tld>. Transports add overlay FQDNs
  # (e.g. a tailnet name) — see kata.mkDomains.
  domains = {
    tld = "example.com";
    locations = {
      # host -> location sub-zone
      edge-01 = "hq";
      server-01 = "hq";
      laptop-01 = "field";
      studio = "hq"; # a darwin workstation
    };
    transports = [ ]; # e.g. [ "tailscale" ] → <host>.tailscale.example.com
    sshUsers = {
      # host -> login user (else defaultSshUser)
      studio = "operator";
    };
    defaultSshUser = "admin";
  };

  # ── People + accounts ─────────────────────────────────────────────────
  users.users = {
    admin = {
      kind = "interactive";
      uid = 1000;
    };
    operator = {
      kind = "interactive";
      uid = 1001;
    };
    automation = {
      kind = "automation";
      uid = 990;
    };
  };

  trust = {
    # SSH public keys trusted fleet-wide on interactive accounts.
    # Replace with YOUR public keys (these are placeholders).
    fleetKeys = [
      # "ssh-ed25519 AAAA...REPLACE_ME admin@example"
    ];
    # Keys for headless deploy / CI accounts.
    automationKeys = [
      # "ssh-ed25519 AAAA...REPLACE_ME ci@example"
    ];
  };

  # ── Machines ──────────────────────────────────────────────────────────
  # One entry per host. `profiles` are names resolved by the flake's profile
  # table (here: lib/profiles.nix). Behavior lives in the profiles + vocabulary,
  # never inline.
  nodes = {
    server-01 = {
      class = "nixos";
      system = "x86_64-linux";
      tags = [ "server" "k3s" ];
      profiles = [ "server-base" "security" ];
      modules = [ ./nodes/server-01 ]; # identity + hardware (per-host)
      deploy = { }; # deploy-rs by default; null = local-only
    };
    edge-01 = {
      class = "nixos";
      system = "x86_64-linux";
      tags = [ "server" "edge" ];
      profiles = [ "server-base" "security" "edge" ];
      modules = [ ./nodes/edge-01 ];
      deploy = { };
    };
    laptop-01 = {
      class = "nixos";
      system = "x86_64-linux";
      tags = [ "agent" "laptop" ];
      profiles = [ "server-base" "security" ];
      modules = [ ./nodes/laptop-01 ];
      deploy = { };
    };
    studio = {
      class = "darwin";
      system = "aarch64-darwin";
      tags = [ "workstation" ];
      profiles = [ "workstation" ];
      modules = [ ./nodes/studio ];
      deploy = null; # darwin hosts deploy locally
    };
  };

  # ── Apps (iroha.mkManifest ecosystem schema) ──────────────────────────
  # One entry per fleet app: drives HM-module imports + overlay registration +
  # profile auto-enables. See substrate/lib/iroha/manifest.nix and
  # docs/PATTERNS.md (the manifest pattern).
  apps = {
    # example-tui = { class = "tui-tool"; };  # programs.example-tui.enable
  };
  appClasses = {
    # "tui-tool" = { profiles = [ "server-base" ]; };
  };

  # ── Binary caches ─────────────────────────────────────────────────────
  caches = [
    # { url = "https://cache.example.com"; publicKey = "cache.example.com-1:..."; }
  ];

  # ── WireGuard links (optional) ────────────────────────────────────────
  # Declare links here and mkFleet exposes `fleet.wireguard` — the per-node
  # projection (linksForNode, secretsForNode, tlsSansForNode, ...). Omit for
  # no VPN. Private keys/PSKs are SOPS paths, never literals.
  vpnLinks = {
    # server-edge = {
    #   interface = "wg-se"; profile = "mesh"; mtu = 1420;
    #   a = { node = "server-01"; address = "10.0.0.1/24"; secrets = { privateKey = "server-01/wg/key"; psk = "se/psk"; }; };
    #   b = { node = "edge-01";   address = "10.0.0.2/24"; secrets.privateKey = "edge-01/wg/key"; };
    # };
  };

  # ── Secrets ───────────────────────────────────────────────────────────
  secrets = {
    backend = "sops";
    # defaultSopsFile = ./secrets.yaml;       # create from secrets.example.yaml
    # ageKeyFile = "/var/lib/sops/age/keys.txt";
  };
}
