# profiles/workstation — a darwin developer workstation ROLE (axis = "role").
#
# Thin example. A real fleet composes blackmatter.components.macos.* + a
# home-manager developer stack here (all enable-flips, no behavior modules).
{ lib, ... }:
{
  system.defaults.NSGlobalDomain.AppleShowAllExtensions = lib.mkDefault true;
  system.defaults.dock.autohide = lib.mkDefault true;

  # Real fleet:
  #   blackmatter.components.macos.developerBase.enable = lib.mkDefault true;
  #   home-manager.sharedModules = [ <your dev HM stack> ];
}
