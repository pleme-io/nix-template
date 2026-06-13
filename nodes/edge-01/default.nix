# nodes/edge-01/ — per-host identity + hardware (the ONLY per-node surface).
#
# Thin: import the hardware truth + set the state version. Profiles (selected in
# fleet.nix) carry the behavior; this dir carries identity + hardware only.
{ lib, ... }:
{
  imports = [ ./hardware-configuration.nix ];
  system.stateVersion = lib.mkDefault "25.11";
  # Per-node overrides (a static IP, an extra disk) go here — nowhere else.
}
