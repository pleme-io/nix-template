# profiles/edge — edge-router ROLE (axis = "role").
#
# Demonstrates the TYPED-ENUM pattern: this profile sets the node's shape and
# gates behavior on the DERIVED facet (config.fleet.mode.isEdge) instead of a
# hand-rolled `mode == "edge"` string check. See modules/node-mode.nix.
{ config, lib, ... }:
let
  inherit (config.fleet.mode) isEdge;
in
{
  fleet.mode.shape = lib.mkDefault "edge";

  networking.nat.enable = lib.mkDefault isEdge;
  boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkIf isEdge (lib.mkDefault 1);

  # Real fleet: an edge-router vocabulary module (NAT, Kea DHCP, blocklist),
  # all gated by the same isEdge facet.
}
