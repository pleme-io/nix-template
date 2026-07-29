# profiles/workstation — a darwin developer workstation ROLE (axis = "role").
#
# Thin example. A real fleet composes blackmatter.components.macos.* + a
# home-manager developer stack here (all enable-flips, no behavior modules).
{ lib, ... }:
{
  # nix-darwin 25.11: every `system.defaults.*` below applies to
  # `system.primaryUser`, and leaving it unset is a hard assertion failure.
  # Declared HERE — in the profile that turns those options on — rather than
  # in the node, so a darwin node that selects this role is never broken by
  # a fact the role itself introduced. Override per-host in `nodes/<name>/`.
  system.primaryUser = lib.mkDefault "operator";

  system.defaults.NSGlobalDomain.AppleShowAllExtensions = lib.mkDefault true;
  system.defaults.dock.autohide = lib.mkDefault true;

  # Real fleet:
  #   blackmatter.components.macos.developerBase.enable = lib.mkDefault true;
  #   home-manager.sharedModules = [ <your dev HM stack> ];
}
