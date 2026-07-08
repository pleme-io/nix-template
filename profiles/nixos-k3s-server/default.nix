# profiles/nixos-k3s-server — a k3s control-plane ROLE (axis = "role").
#
# Stacks on server-base. Turns a node into a K3s control-plane ("server")
# node using the GENERIC nixpkgs `services.k3s` options directly — the
# load-bearing, standalone-evaluable core of the pattern.
#
# TWO teaching points fused here:
#
#   1. The TYPED-ENUM node shape (modules/node-mode.nix). This role sets
#      `fleet.mode.shape = "server"` and gates its GUI-free posture on the
#      DERIVED `isHeadless` facet, instead of a hand-rolled `mode == "..."`
#      string check. A typo in the shape is an EVAL error, not a silent
#      wrong-boot.
#
#   2. A THIN k3s role: enable-flips + typed settings over the `services.k3s`
#      vocabulary. A real fleet swaps the raw `services.k3s` block for its
#      own behavior module (e.g. `services.blackmatter.k3s`) — that module
#      owns the wait-for-DNS gate, the mesh/istio profile, GPU toggles, the
#      kubeconfig-export service, and the CPU/NVMe/getty optimization bundle.
#      Here we keep the generic upstream path live so the example evaluates
#      against plain nixpkgs.
{ config, lib, pkgs, ... }:
let
  inherit (config.fleet.mode) isHeadless;
in
{
  # ── Node shape: this role is a headless control-plane node ─────────────
  # Flip this one value; the isHeadless / isDesktop / isEdge / isAgent facets
  # in modules/node-mode.nix all follow. mkDefault lets a node override
  # (e.g. to "desktop" for a control-plane box that also runs a GUI).
  fleet.mode.shape = lib.mkDefault "server";

  # ── K8s requires no swap ───────────────────────────────────────────────
  swapDevices = lib.mkDefault [ ];

  # ── K3s control plane (generic nixpkgs options — LIVE) ─────────────────
  services.k3s = {
    enable = lib.mkDefault true;
    role = lib.mkDefault "server";

    # extraFlags is where cluster networking + role knobs live upstream.
    # The CIDRs below are the K3s defaults, spelled out so the shape of a
    # real override is visible. A node overrides any of these directly.
    extraFlags = lib.mkDefault [
      "--cluster-cidr=10.42.0.0/16"     # pod network
      "--service-cidr=10.43.0.0/16"     # ClusterIP service network
      "--cluster-dns=10.43.0.10"        # in-cluster CoreDNS address
      # Real fleet often disables the bundled stack in favour of a mesh:
      #   "--disable=traefik"
      #   "--flannel-backend=none"       # CNI supplied by the mesh instead
    ];

    # ── Joining an EXISTING control plane (sanitized placeholders) ────────
    # For a SECONDARY server or an AGENT node, point at the primary's API
    # and supply the cluster token. NEVER commit a real token to a public
    # repo — source it from a secret (sops-nix / agenix) and reference the
    # rendered path here. Left commented so the single-server example above
    # stays self-contained and evaluable.
    #
    #   serverAddr = "https://10.0.0.10:6443";     # primary API endpoint
    #   tokenFile  = config.sops.secrets."k3s/cluster-token".path;
  };

  # kubectl + attic-client are the minimum useful tools on a control-plane
  # box. Generic; a real fleet folds these into its packages vocabulary.
  environment.systemPackages = lib.mkDefault (with pkgs; [ kubectl ]);

  # A control-plane node has no desktop. Gate GUI-off on the DERIVED facet,
  # not a re-parsed string — this is the whole point of the typed enum.
  services.xserver.enable = lib.mkForce (!isHeadless);

  # ── What a real fleet layers on top (behavior vocabulary — commented) ──
  # These are the blackmatter/pleme lines this thin profile stands in for.
  # They are NOT wired here so the template evaluates against plain nixpkgs.
  #
  #   # Typed k3s server module: wait-for-DNS gate, mesh profile, GPU, the
  #   # kubeconfig-export service, CPU/NVMe/getty optimizations, kubectl aliases.
  #   pleme.nixos.k3s.enable = true;
  #   pleme.nixos.k3s.distribution = "1.34";   # override, no mkForce
  #   pleme.nixos.k3s.profile = "istio-mesh";
  #
  #   # Colocated Nix remote builder — a control-plane node is also a build
  #   # host in this fleet; a node opts out with `enable = false`.
  #   pleme.nixos.builder.enable = lib.mkDefault true;
  #
  #   # Per-user home-manager additions for the server role live under ./home
  #   # and are attached by the fleet's user registry (kata mkUsers), keyed on
  #   # the node's configured user name — never a hard-coded username here.
}
