# profiles/nixos-gnome-desktop/home/default.nix
#
# Per-user GNOME tweaks for the styled desktop. stylix already themes the
# shell/GTK/cursor/icons and sets dark mode from the base16 palette; this
# layers the "modern, comfortable" behaviour on top: dark confirmed, hot
# corners off, tap-to-click, dynamic workspaces + edge tiling, and the
# extensions the system profile installs (tray icons, a real dock, blur).
#
# Pure dconf — no vocabulary dependency, evaluates on plain home-manager.
{ ... }: {
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      enable-hot-corners = false;
      clock-show-weekday = true;
      show-battery-percentage = true;
    };

    # NOTE: setting a custom default terminal (incl. GNOME's "Open Terminal")
    # is best owned by a SINGLE fleet-wide seam so every desktop node gets it
    # from one place, rather than being redeclared per profile.

    "org/gnome/desktop/peripherals/touchpad" = {
      tap-to-click = true;
      natural-scroll = true;
      two-finger-scrolling-enabled = true;
    };

    "org/gnome/desktop/wm/preferences" = {
      button-layout = "appmenu:minimize,maximize,close";
      focus-mode = "click";
    };

    "org/gnome/mutter" = {
      dynamic-workspaces = true;
      edge-tiling = true;
      center-new-windows = true;
    };

    "org/gnome/shell" = {
      disable-user-extensions = false;
      enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com"
        "dash-to-dock@micxgx.gmail.com"
        "blur-my-shell@aunetx"
        "user-theme@gnome-shell-extensions.gcampax.github.com"
      ];
    };

    "org/gnome/shell/extensions/dash-to-dock" = {
      dock-position = "BOTTOM";
      extend-height = false;
      transparency-mode = "DYNAMIC";
      running-indicator-style = "DOTS";
      show-trash = false;
      click-action = "minimize-or-previews";
    };
  };
}
