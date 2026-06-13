# lib/profiles.nix — the SINGLE PROFILE CATALOG pattern.
#
# ONE typed registry of every profile: name -> { class, axis, module }. This is
# the single place profiles are declared and the single interface they resolve
# through (`table` feeds mkFleet's profile table in flake.nix). A name maps to
# exactly one module — the doubling of "two ways to select a profile" is
# unrepresentable here.
#
# `axis` is the iroha authority band (base < hardware < mixin < role < node):
# composition precedence is encoded in the TYPE, so a base foundation yields to
# a role profile by construction rather than a runtime "conflicting definition
# values". (In this example the profiles are thin enough not to collide; the
# axis is declared so the pattern is visible.)
{ lib }:
let
  validClasses = [ "nixos" "darwin" "hm" ];
  validAxes = [ "base" "hardware" "mixin" "role" "node" ];

  mkEntry = name: spec:
    assert lib.assertMsg (builtins.elem spec.class validClasses)
      "profiles: '${name}'.class='${spec.class}' invalid (${lib.concatStringsSep ", " validClasses})";
    assert lib.assertMsg (builtins.elem spec.axis validAxes)
      "profiles: '${name}'.axis='${spec.axis}' invalid (${lib.concatStringsSep ", " validAxes})";
    { inherit name; inherit (spec) class axis module; };

  entries = lib.mapAttrs mkEntry {
    "server-base" = { class = "nixos"; axis = "base"; module = ../profiles/server-base.nix; };
    "security" = { class = "nixos"; axis = "mixin"; module = ../profiles/security.nix; };
    "edge" = { class = "nixos"; axis = "role"; module = ../profiles/edge.nix; };
    "workstation" = { class = "darwin"; axis = "role"; module = ../profiles/workstation.nix; };
  };

  names = builtins.attrNames entries;
in
{
  inherit entries names;

  # The single interface: name -> module (typed throw on unknown).
  module = name:
    (entries.${name} or (throw "profiles: unknown profile '${name}' — known: ${lib.concatStringsSep ", " names}")).module;

  # The mkFleet profile table: { "<name>" = <module>; }.
  table = lib.mapAttrs (_: e: e.module) entries;

  catalog = {
    inherit names;
    count = builtins.length names;
    byAxis = lib.groupBy (n: entries.${n}.axis) names;
    axisOrder = validAxes;
  };
}
