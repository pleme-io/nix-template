# nodes/server-01/hardware-configuration.nix — PLACEHOLDER.
#
# REPLACE this with the real output of `nixos-generate-config` (or your disko
# layout) on the actual machine. This stub only lets the example EVALUATE; it
# will NOT boot a real system. The block-device UUIDs, partition layout, and
# kernel modules are the one truly per-host, un-templatable fact.
{ lib, ... }:
{
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos"; # REPLACE with a real device/UUID
    fsType = "ext4";
  };
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
