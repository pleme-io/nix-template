# profiles/security — a thin hardening MIXIN (axis = "mixin").
#
# Profiles in a fleet repo are THIN: enable-flips + settings over vocabulary,
# pinned to a priority axis, never behavior modules. This example uses plain
# nixpkgs options; a real fleet prefers blackmatter-security components.
{ lib, ... }:
{
  services.fail2ban.enable = lib.mkDefault true;
  services.openssh.settings.PasswordAuthentication = lib.mkDefault false;
  services.openssh.settings.PermitRootLogin = lib.mkDefault "prohibit-password";

  # Real fleet (once you import the vocabulary):
  #   blackmatter.components.security.hardening.enable = lib.mkDefault true;
}
