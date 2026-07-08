# lib/base16-scheme.nix
#
# The fleet's canonical stylix base16 scheme, sourced ONCE so every stylix
# consumer (here: the GNOME desktop profile — in a real fleet, also the Darwin
# workstations and the Rust GUI apps) reads the same palette and the wiring
# can't drift between them. This example uses the "nord" scheme shipped by
# nixpkgs `base16-schemes`; swap the filename for any other scheme in that
# package (black-metal, gruvbox-dark-medium, tomorrow-night, ...).
#
# ★ THE LOAD-BEARING LESSON — always pass `{ yaml = <path-or-drv>; }`, never
#   a bare derivation.
#
#   stylix's base16.nix classifies its input with
#     is-not-parsed = builtins.isAttrs scheme && !(scheme ? "yaml")
#   A derivation IS an attrset, so a bare `pkgs.base16-schemes` (or a bare
#   scheme derivation from a flake input) is MISTAKEN for an already-parsed
#   `{ base00 = …; base01 = …; … }` colour set and throws
#     ("mkSchemeAttrs … parse result: /nix/store/…").
#   A bare path/drv only ever "works" by accident when the file happens to be
#   pre-realized in the store; a GC or an input bump then breaks it.
#
#   Wrapping the path as `{ yaml = <path>; }` sets base16.nix's `is-y2a-args`
#   branch, so its yaml2attrs does `readFile <path>` — it reads and PARSES the
#   rendered YAML into the colour set. Robust regardless of realization state.
#   Rule of thumb: whenever you hand stylix a scheme file, hand it as
#   `{ yaml = <the .yaml path>; }`.
{ pkgs }:
{
  yaml = "${pkgs.base16-schemes}/share/themes/nord.yaml";
}
