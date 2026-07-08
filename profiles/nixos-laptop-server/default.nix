# profiles/nixos-laptop-server — laptop-as-server ROLE (axis = "role").
#
# Turns a laptop into a headless always-on server node: WiFi via
# NetworkManager, TLP power management, and USB tethering as a failover
# uplink. The classic "old laptop in a closet running k3s" pattern — its
# built-in battery is a free UPS and the lid closes without sleeping.
#
# Demonstrates the TYPED-ENUM pattern (see modules/node-mode.nix): this
# profile sets the node's shape to "agent" and gates behavior on the DERIVED
# facet (config.fleet.mode.isAgent) instead of a hand-rolled string check.
#
# The nixpkgs options below are GENERIC and evaluate against plain nixpkgs.
# In the real fleet these flips are owned by blackmatter vocabulary (named in
# comments) — a fleet repo profile is THIN: enable-flips + settings, never a
# behavior module.
{ config, lib, ... }:
let
  inherit (config.fleet.mode) isAgent;
in
{
  # Declare the shape; every facet (isAgent, isHeadless, ...) follows from it.
  fleet.mode.shape = lib.mkDefault "agent";

  # ── WiFi via NetworkManager ──────────────────────────────────────
  # A laptop's uplink is usually wireless. NetworkManager owns the WiFi
  # association; keep power-save OFF so a server-role node never parks the
  # radio mid-idle and drops connectivity.
  networking.networkmanager.enable = lib.mkDefault isAgent;
  networking.networkmanager.wifi.powersave = lib.mkDefault false;

  # ── TLP power management ──────────────────────────────────────────
  # A closed-lid always-on laptop still benefits from TLP: cap thermals and
  # keep the battery healthy on permanent AC. Default profile is fine; a node
  # tunes CPU governor / charge thresholds via services.tlp.settings.
  services.tlp.enable = lib.mkDefault isAgent;

  # ── USB tethering (failover uplink) ───────────────────────────────
  # A phone on USB shows up as a usb-ethernet gadget — a cheap backup WAN when
  # the WiFi AP is down. usbmuxd covers iOS personal-hotspot pairing; the RNDIS
  # / CDC-ECM gadget drivers are in the default kernel, no extra module needed.
  services.usbmuxd.enable = lib.mkDefault isAgent;

  # Keep the lid-close from suspending a headless server node.
  services.logind.settings.Login.HandleLidSwitch = lib.mkDefault "ignore";

  # Real fleet (once you import the vocabulary): all of the above collapse to
  # one typed module flip, which fans out to the blizzard networking pipeline:
  #   pleme.nixos.laptop.enable = true;
  #     -> blackmatter.profiles.blizzard.networkingExtended.networkManager.enable
  #     -> blackmatter.profiles.blizzard.laptopServer.{tlp,usbTethering}
  # Per-node overrides then read as `pleme.nixos.laptop.tlp = false;` etc.
}
