# nodes/studio/ — darwin workstation identity. No hardware-configuration.nix on
# macOS (nix-darwin manages the system); per-host overrides go here.
{ lib, ... }:
{
  system.stateVersion = lib.mkDefault 5; # nix-darwin stateVersion (integer)
}
