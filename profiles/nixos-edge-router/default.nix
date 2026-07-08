# profiles/nixos-edge-router — WAN<->LAN edge-router ROLE (axis = "role").
#
# Turns a node into the home's edge router, sitting between the ISP modem
# (in bridge mode) and downstream switches / WiFi APs:
#
#   - nftables firewall + SNAT/masquerade  WAN -> LAN
#   - kernel IP forwarding + conntrack + rp_filter tuning
#   - Kea DHCP4 server on the LAN interface
#   - a weekly ad/tracker blocklist-refresh timer (feeds a DNS resolver)
#   - VLAN stub interfaces on the LAN uplink with per-zone egress policy
#   - optional Suricata IDS on the WAN interface (off by default)
#
# Demonstrates the TYPED-ENUM pattern (see modules/node-mode.nix): sets the
# node's shape to "edge" and gates every rule on the DERIVED facet
# (config.fleet.mode.isEdge). A node also picks its physical NICs by setting
# `fleet.edgeRouter.interfaces.{wan,lan}` — the placeholder enpXsY defaults
# keep this profile standalone-evaluable; a real node overrides them.
#
# What this does NOT do: replace the DNS resolver (the blocklist output is
# meant to be included by whatever dnsmasq/unbound you already run), configure
# the ISP modem (put it in bridge mode externally), or handle IPv6 PD.
#
# The nixpkgs options below are GENERIC and evaluate against plain nixpkgs.
# In the real fleet the whole ruleset is owned by a `pleme.nixos.edgeRouter`
# vocabulary module (named in comments) and a Rust blocklist tool; a fleet
# repo profile is THIN — this file is the worked example of the behavior that
# module encapsulates.
{ config, lib, pkgs, ... }:
let
  inherit (config.fleet.mode) isEdge;
  cfg = config.fleet.edgeRouter;

  # Derive the first-three-octets base from a CIDR, e.g. "10.0.60.0/24" -> "10.0.60".
  cidrBase = cidr:
    let parts = lib.splitString "." (builtins.elemAt (lib.splitString "/" cidr) 0);
    in "${builtins.elemAt parts 0}.${builtins.elemAt parts 1}.${builtins.elemAt parts 2}";

  # Split an "addr/prefix" string into the { address; prefixLength; } shape.
  splitAddr = a:
    let parts = lib.splitString "/" a;
    in { address = builtins.elemAt parts 0; prefixLength = lib.toInt (builtins.elemAt parts 1); };

  gwOf = a: builtins.elemAt (lib.splitString "/" a) 0;
in
{
  # ── Typed knobs a node overrides (placeholder defaults) ──────────
  options.fleet.edgeRouter = {
    interfaces = {
      wan = lib.mkOption {
        type = lib.types.str;
        default = "enp1s0";
        example = "enp1s0";
        description = "Uplink NIC facing the ISP modem (DHCP client).";
      };
      lan = lib.mkOption {
        type = lib.types.str;
        default = "enp2s0";
        example = "enp2s0";
        description = "Downlink NIC facing the home LAN / managed switch.";
      };
    };

    lanSubnet = lib.mkOption {
      type = lib.types.str;
      default = "10.0.60.0/24";
      description = "LAN subnet in CIDR form (drives SNAT match + DHCP pool).";
    };

    lanAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.0.60.1/24";
      description = "Static address assigned to the LAN interface (the gateway).";
    };

    # VLAN segments carried on the LAN trunk. Each becomes a <lan>.<id>
    # interface with an independent firewall zone + DHCP pool. DMZ / IoT
    # typically get egress but are isolated from the trusted LAN.
    vlans = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          id = lib.mkOption { type = lib.types.int; description = "VLAN ID (1-4094)."; };
          subnet = lib.mkOption { type = lib.types.str; description = "CIDR for this VLAN."; };
          address = lib.mkOption { type = lib.types.str; description = "Router address on this VLAN."; };
          egressAllowed = lib.mkOption { type = lib.types.bool; default = true; description = "Hosts may reach the WAN."; };
          reachesLan = lib.mkOption { type = lib.types.bool; default = false; description = "Hosts may initiate into the trusted LAN."; };
        };
      });
      default = { };
      example = lib.literalExpression ''
        {
          iot = { id = 20; subnet = "10.0.62.0/24"; address = "10.0.62.1/24"; egressAllowed = true; reachesLan = false; };
          dmz = { id = 30; subnet = "10.0.63.0/24"; address = "10.0.63.1/24"; egressAllowed = true; reachesLan = false; };
        }
      '';
      description = "VLAN segments on the LAN trunk, each with its own zone + pool.";
    };

    dhcp.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run the Kea DHCP4 server on the LAN / VLAN interfaces.";
    };

    dhcp.leaseTime = lib.mkOption {
      type = lib.types.int;
      default = 3600;
      description = "DHCP lease time (seconds).";
    };

    blocklist.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Fetch an ad/tracker hosts blocklist on a timer for your resolver to include.";
    };

    blocklist.urls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" ];
      description = "Hosts-format blocklist URLs fetched to /var/lib/dnsmasq/blocklist.hosts.";
    };

    blocklist.refreshSchedule = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "systemd OnCalendar for the blocklist refresh.";
    };

    ids.suricata.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable a Suricata IDS on the WAN interface.";
    };

    extraNftables = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra nftables rules appended at the end of the ruleset.";
    };
  };

  # The shape is declared UNGATED (mkDefault, so a mode-toggled node can still
  # flip it). It must live outside the `mkIf isEdge` below: `isEdge` is derived
  # FROM `fleet.mode.shape`, so setting the shape inside its own conditional
  # would be an infinite recursion. The behavior block is what gets gated.
  config = lib.mkMerge [
    { fleet.mode.shape = lib.mkDefault "edge"; }

    # Everything below is gated on the derived isEdge facet — flip the node's
    # shape to "edge" (this profile's default) to turn it all on at once.
    (lib.mkIf isEdge {
    # ── Kernel: IP forwarding, conntrack, rp_filter ──────────────────
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv4.conf.all.rp_filter" = 1;
      "net.ipv4.conf.default.rp_filter" = 1;
      "net.netfilter.nf_conntrack_max" = 524288;
      "net.core.netdev_max_backlog" = 16384;
    };

    # ── Interface addresses + VLAN sub-interfaces ────────────────────
    # WAN is a DHCP client from the ISP modem (leave it to the default DHCP
    # client — we do not configure it here). LAN is static at the gateway;
    # each VLAN gets a <lan>.<id> stub interface with its own router address.
    networking.vlans = lib.mapAttrs' (_: v:
      lib.nameValuePair "${cfg.interfaces.lan}.${toString v.id}" {
        id = v.id;
        interface = cfg.interfaces.lan;
      }) cfg.vlans;

    networking.interfaces =
      {
        ${cfg.interfaces.lan}.ipv4.addresses = [ (splitAddr cfg.lanAddress) ];
      }
      // (lib.mapAttrs' (_: v:
        lib.nameValuePair "${cfg.interfaces.lan}.${toString v.id}" {
          ipv4.addresses = [ (splitAddr v.address) ];
        }) cfg.vlans);

    # ── nftables: NAT + inter-zone policy ────────────────────────────
    # nftables owns the netfilter hooks here, so the simple stateful firewall
    # is disabled — the ruleset below is the single source of truth.
    networking.firewall.enable = lib.mkForce false;
    networking.nftables = {
      enable = true;
      ruleset = ''
        table inet filter {
          chain input {
            type filter hook input priority 0; policy drop;
            ct state established,related accept
            iifname "lo" accept
            iifname "${cfg.interfaces.lan}" accept
            icmp type { echo-request, echo-reply } accept
            icmpv6 type { echo-request, echo-reply, nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert } accept
            # SSH and the k8s API — reachable on the router itself.
            tcp dport { 22 } accept
            tcp dport { 6443 } accept
            # WireGuard listen ports (adjust to your links).
            udp dport { 51820, 51821, 51822, 51823 } accept
            counter drop
          }

          chain forward {
            type filter hook forward priority 0; policy drop;
            ct state established,related accept
            # LAN -> WAN: allow.
            iifname "${cfg.interfaces.lan}" oifname "${cfg.interfaces.wan}" accept
            # VLAN egress per policy.
            ${lib.concatMapStringsSep "\n            " (name:
              let v = cfg.vlans.${name}; in
              lib.optionalString v.egressAllowed
                ''iifname "${cfg.interfaces.lan}.${toString v.id}" oifname "${cfg.interfaces.wan}" accept'')
              (lib.attrNames cfg.vlans)}
            # VLAN -> LAN crossings (deny by default; opt in per VLAN).
            ${lib.concatMapStringsSep "\n            " (name:
              let v = cfg.vlans.${name}; in
              lib.optionalString v.reachesLan
                ''iifname "${cfg.interfaces.lan}.${toString v.id}" oifname "${cfg.interfaces.lan}" accept'')
              (lib.attrNames cfg.vlans)}
            counter drop
          }

          chain output {
            type filter hook output priority 0; policy accept;
          }
        }

        table ip nat {
          chain prerouting {
            type nat hook prerouting priority -100;
          }

          chain postrouting {
            type nat hook postrouting priority 100;
            oifname "${cfg.interfaces.wan}" masquerade
          }
        }

        ${cfg.extraNftables}
      '';
    };

    # ── Kea DHCP4 ────────────────────────────────────────────────────
    services.kea.dhcp4 = lib.mkIf cfg.dhcp.enable {
      enable = true;
      settings = {
        interfaces-config.interfaces = [ cfg.interfaces.lan ]
          ++ (lib.mapAttrsToList (_: v: "${cfg.interfaces.lan}.${toString v.id}") cfg.vlans);
        lease-database = {
          type = "memfile";
          persist = true;
          name = "/var/lib/kea/dhcp4.leases";
        };
        valid-lifetime = cfg.dhcp.leaseTime;
        subnet4 = [
          {
            subnet = cfg.lanSubnet;
            pools = [{ pool = "${cidrBase cfg.lanSubnet}.100 - ${cidrBase cfg.lanSubnet}.250"; }];
            option-data = [
              { name = "routers"; data = gwOf cfg.lanAddress; }
              { name = "domain-name-servers"; data = gwOf cfg.lanAddress; }
            ];
          }
        ] ++ (lib.mapAttrsToList (_: v: {
          subnet = v.subnet;
          interface = "${cfg.interfaces.lan}.${toString v.id}";
          pools = [{ pool = "${cidrBase v.subnet}.100 - ${cidrBase v.subnet}.250"; }];
          option-data = [
            { name = "routers"; data = gwOf v.address; }
            { name = "domain-name-servers"; data = gwOf v.address; }
          ];
        }) cfg.vlans);
      };
    };

    # ── Blocklist refresh timer ──────────────────────────────────────
    # A weekly oneshot fetches a hosts-format blocklist to a file your resolver
    # includes (dnsmasq addn-hosts / unbound include). This example uses a tiny
    # curl+awk pipeline; the real fleet replaces it with a Rust blocklist tool
    # (execution-verified, best-effort fetch, 0.0.0.0/127.0.0.1 filter, dedup).
    systemd.services.edge-router-blocklist-refresh = lib.mkIf cfg.blocklist.enable {
      description = "Fetch and assemble the dnsmasq ad/tracker blocklist";
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "dnsmasq";
        ExecStart = pkgs.writeShellScript "blocklist-refresh" ''
          set -eu
          out=/var/lib/dnsmasq/blocklist.hosts
          tmp=$(mktemp)
          for url in ${lib.escapeShellArgs cfg.blocklist.urls}; do
            ${pkgs.curl}/bin/curl -fsSL "$url" >> "$tmp" || true
          done
          ${pkgs.gawk}/bin/awk '/^0\.0\.0\.0|^127\.0\.0\.1/ {print}' "$tmp" \
            | sort -u > "$out"
          rm -f "$tmp"
        '';
      };
    };

    systemd.timers.edge-router-blocklist-refresh = lib.mkIf cfg.blocklist.enable {
      description = "Weekly blocklist refresh";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.blocklist.refreshSchedule;
        Persistent = true;
      };
    };

    # Real fleet: point your resolver at the output file, e.g.
    #   pleme.nixos.k3s.dns.extraSettings.addn-hosts = "/var/lib/dnsmasq/blocklist.hosts";

    # ── Suricata IDS (optional, default off) ─────────────────────────
    services.suricata = lib.mkIf cfg.ids.suricata.enable {
      enable = true;
      settings = {
        af-packet = [{
          interface = cfg.interfaces.wan;
          threads = "auto";
          cluster-id = 99;
          cluster-type = "cluster_flow";
          defrag = "yes";
        }];
      };
    };

    # ── Edge-router operator toolbox ─────────────────────────────────
    environment.systemPackages = with pkgs; [
      nftables conntrack-tools tcpdump ethtool dig bind.dnsutils
      iftop bandwhich mtr
    ];

    # Real fleet (once you import the vocabulary): the entire block above is
    # one typed module flip that fans the ruleset through the blizzard
    # networking pipeline and a Rust blocklist tool:
    #   pleme.nixos.edgeRouter.enable = true;
    #   pleme.nixos.edgeRouter.interfaces = { wan = "enp1s0"; lan = "enp2s0"; };
    })
  ];
}
