# modules/node-mode.nix — the TYPED-ENUM pattern.
#
# A node's runtime "shape" as ONE validated enum + derived facets, instead of a
# bare string toggle with hand-rolled `mode == "..."` predicates. A typo is an
# EVAL error, not a silent wrong-boot. This is the type-strict pattern: make the
# illegal value unrepresentable.
#
# Reusable as-is. Set `fleet.mode.shape` in a node/profile; read the derived
# `fleet.mode.{isDesktop,isEdge,isAgent,isHeadless}` facets wherever you gate.
{ config, lib, ... }:
let
  cfg = config.fleet.mode;
  desktopShapes = [ "desktop" "agent-desktop" ];
  agentShapes = [ "agent" "agent-desktop" ];
in
{
  options.fleet.mode = {
    shape = lib.mkOption {
      type = lib.types.enum [ "server" "edge" "desktop" "agent" "agent-desktop" ];
      default = "server";
      description = ''
        The node's runtime shape — ONE canonical vocabulary fleet-wide:
          server        — headless server (no GUI, no edge router)
          edge          — server + edge-router role (NAT / DHCP / blocklist)
          desktop       — server + GUI workstation
          agent         — headless laptop agent (TLP, WiFi)
          agent-desktop — agent + GUI (local debugging)
        Flip this one value; every facet below follows.
      '';
    };

    # Derived facets — read-only, computed from shape, never set directly.
    isDesktop = lib.mkOption { type = lib.types.bool; internal = true; readOnly = true; description = "GUI facet."; };
    isEdge = lib.mkOption { type = lib.types.bool; internal = true; readOnly = true; description = "Edge-router facet."; };
    isAgent = lib.mkOption { type = lib.types.bool; internal = true; readOnly = true; description = "Laptop-agent facet."; };
    isHeadless = lib.mkOption { type = lib.types.bool; internal = true; readOnly = true; description = "No-GUI facet."; };
  };

  config.fleet.mode = {
    isDesktop = builtins.elem cfg.shape desktopShapes;
    isEdge = cfg.shape == "edge";
    isAgent = builtins.elem cfg.shape agentShapes;
    isHeadless = !(builtins.elem cfg.shape desktopShapes);
  };
}
