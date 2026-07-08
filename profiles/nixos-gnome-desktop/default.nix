# profiles/nixos-gnome-desktop — a fully-styled GNOME desktop ROLE
# (axis = "role").
#
# A modern, fully-themed GNOME-on-Wayland desktop: GDM, dash-to-dock, blur,
# tweaks, PipeWire audio, a Nerd-Font stack, and stylix auto-theming every
# GNOME/GDM/GTK/cursor/icon target from ONE base16 palette (lib/base16-scheme.nix).
#
# WHY it's a full module (not a thin flip like the other example profiles):
# a desktop role owns a whole stack — display manager, audio, fonts, theming,
# per-user dconf. That's a legitimate role-axis profile. What stays thin is the
# BEHAVIOR that in a real fleet comes from vocabulary (blackmatter DE profiles,
# an ishou font/palette input) — those are left as comments in the house style.
#
# Standalone-evaluable: every option below is plain nixpkgs + the public stylix
# input. Opt a node in by listing "nixos-gnome-desktop" in its profile stack.
{ config, lib, pkgs, ... }:
{
  # stylix's NixOS module is imported once in the flake's node base (flake.nix),
  # where the `inputs` are in scope — kata does not thread `inputs` into node
  # modules' specialArgs, so referencing `inputs.stylix…` in a profile's
  # `imports` would infinite-recurse. The module is inert unless `stylix.enable`
  # (below) is set, so every node carrying it pays nothing until it opts in.

  # ── GNOME on Wayland via GDM ──────────────────────────────────
  services.xserver.enable = true;            # xkb + Xwayland support
  services.xserver.xkb = { layout = "us"; options = "caps:escape"; };
  services.displayManager.gdm = { enable = true; wayland = true; };
  services.desktopManager.gnome.enable = true;

  # ── Be the SOLE desktop ───────────────────────────────────────
  # In a real fleet a base workstation profile might ship a competing DE
  # (Hyprland / niri / COSMIC). When this role is selected, force those off so
  # nothing else fights for the seat. The plain-nixpkgs option that always
  # applies:
  services.displayManager.sddm.enable = lib.mkForce false;
  #
  # Real fleet (once you import the DE vocabulary), the same idiom:
  #   programs.hyprland.enable = lib.mkForce false;
  #   programs.niri.enable = lib.mkForce false;
  #   services.desktopManager.cosmic.enable = lib.mkForce false;
  #   blackmatter.profiles.blizzard.xserver.enable = lib.mkForce false;

  # ── Essential desktop services ────────────────────────────────
  services.dbus.enable = true;
  hardware.graphics.enable = true;
  security.rtkit.enable = true;
  services.libinput.enable = true;
  # mkForce, not mkDefault: a base "server" profile may set
  # `services.printing.enable = mkDefault false`, which collides with a
  # mkDefault here (same priority → eval conflict). The GNOME role owns the
  # desktop stack when enabled, so it wins — same idiom as the DE-disable
  # mkForces above.
  services.printing.enable = lib.mkForce true;
  services.gnome.gnome-keyring.enable = true;
  networking.networkmanager.enable = lib.mkDefault true;
  # nixpkgs' GNOME desktop-manager turns bluetooth ON (plain true); a fleet
  # base-system-tuning profile often turns it OFF (plain false) — same
  # priority, so they collide on a GNOME node. A personal desktop wants
  # bluetooth (headphones/mouse/keyboard), and the GNOME role owns desktop
  # concerns, so force it on.
  hardware.bluetooth.enable = lib.mkForce true;
  # Same conflict for Thunderbolt device management: nixpkgs' GNOME enables
  # `services.hardware.bolt` (mkDefault true), a base profile may disable it
  # (mkDefault false). A desktop wants it — force it on.
  services.hardware.bolt.enable = lib.mkForce true;
  # GNOME ships its own xdg portal; just turn the portal stack on.
  xdg.portal.enable = true;

  # Audio via PipeWire (GNOME's default expectation).
  services.pulseaudio.enable = lib.mkForce false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ── Trim GNOME bloat ──────────────────────────────────────────
  environment.gnome.excludePackages = with pkgs; [
    gnome-tour gnome-connections epiphany geary gnome-music
    gnome-maps gnome-weather totem yelp
  ];

  # ── GNOME tooling + theming extras ────────────────────────────
  environment.systemPackages = with pkgs; [
    gnome-tweaks
    dconf-editor
    gnome-shell-extensions
    gnomeExtensions.appindicator        # tray icons (for TUI/daemons)
    gnomeExtensions.dash-to-dock         # modern dock
    gnomeExtensions.blur-my-shell        # modern translucency
    adwaita-icon-theme
    papirus-icon-theme
    networkmanagerapplet
    seahorse
  ];

  # ── Fonts (a Nerd-Font stack + emoji + fallbacks) ─────────────
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    fira-code
    jetbrains-mono
    inter
    noto-fonts
    noto-fonts-color-emoji
    dejavu_fonts
    liberation_ttf
  ];

  # ── Styling — one base16 palette, fleet-wide ──────────────────
  # stylix auto-detects and themes the GNOME Shell, GDM, GTK 3/4, cursor, and
  # icon targets from a SINGLE base16 scheme, and propagates to home-manager
  # automatically. `image` is a solid base00 fill (no external wallpaper to
  # drift); flip it to a real image path if you want one.
  stylix = {
    enable = true;
    polarity = "dark";
    # ★ THE `{ yaml = <path>; }` FORM — a bare derivation is misread by
    #   stylix's base16.nix as an already-parsed colour set. See the load-
    #   bearing lesson in lib/base16-scheme.nix.
    base16Scheme = import ../../lib/base16-scheme.nix { inherit pkgs; };
    # Real fleet: source fonts from your shared font/palette input, e.g.
    #   fonts = import inputs.ishou.packages.${pkgs.stdenv.hostPlatform.system}.stylix-fonts { inherit pkgs; };
    # The default (nixpkgs DejaVu/monospace) is themed fine out of the box.
    image = config.lib.stylix.pixel "base00";
  };

  # ── Wire the per-user GNOME tweaks (dark mode + extensions + tap) ──
  # In a real fleet this reads the node's primary username from your typed
  # user surface (e.g. `config.pleme.nixos.base.user.name`). The template's
  # canonical example user is "admin".
  home-manager.users.admin.imports = [ ./home ];
}
