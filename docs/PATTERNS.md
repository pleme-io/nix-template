# The patterns this template demonstrates

A fleet repo is **private configuration over a shared, typed vocabulary**. The
whole point: write your fleet's *facts* once, in `fleet.nix`, and let the
vocabulary mechanically derive every system from them. These are the patterns
that make that work — each one is "one system, one interface, type-strict."

## 1. The three tiers

```
GENERIC VOCABULARY        →  COMPOSED ARCHETYPES   →  PRIVATE INSTANCE
(substrate / blackmatter)    (profiles + catalog)     (fleet.nix + nodes/ + secrets)
  kata.* / iroha.*             thin enable-flips        the blanks, hardware, keys
  (flake inputs)               (this repo, generic-ish) (this repo, YOURS)
```

You **import** tier 1, **select/copy** tier 2, and **author only** tier 3.

## 2. The blanks (`fleet.nix`) — type-strict by construction

Every fleet-specific fact lives in `fleet.nix`, validated against kata's strict
schema. An unknown key or a wrong type **fails evaluation with a named error** —
the typo is unrepresentable, not silently ignored. `kata.mkFleet` turns the
blanks into `nixosConfigurations` + `darwinConfigurations` + deploy data + ssh
aliases + the WireGuard projection + a typed `report`, from ONE call.

## 3. Thin profiles (`profiles/*.nix`)

Profiles are **enable-flips + settings** over the vocabulary, pinned to a
priority axis — never behavior modules. If behavior wants to live in a profile,
it belongs in the vocabulary (a blackmatter component / kata-iroha letter)
instead. `mkDefault` everywhere, so a node overrides cleanly.

## 4. The profile catalog (`lib/profiles.nix`) — ONE interface

A single typed registry: `name -> { class, axis, module }`. It's the *only* way
a profile is selected — nodes name profiles, the catalog resolves them (typed
throw on an unknown name). A profile name maps to exactly one module, so "two
ways to select a profile" is unrepresentable. `axis` encodes composition
precedence (`base < hardware < mixin < role < node`) in the type.

## 5. The typed-enum (`modules/node-mode.nix`)

A node's runtime "shape" is ONE `types.enum` + derived facets
(`isDesktop`/`isEdge`/`isAgent`/`isHeadless`), not a bare-string toggle with
hand-rolled `mode == "..."` predicates. A typo is an eval error. Profiles gate
on the facets (`profiles/edge.nix` is the worked example). This is the
type-strict move: make the illegal value unrepresentable.

## 6. The app manifest (`fleet.nix` `apps`)

One typed entry per fleet app drives HM-module imports + overlay registration +
profile auto-enables (`iroha.mkManifest`). The manifest is the single source of
"which apps this fleet runs and how they wire in" — no parallel hand-lists.

## The forward rule

A new concept ships as **one system + one interface + a `types.*` schema**, with
a check asserting its invariants. A second way to declare an existing concept is
the doubling these patterns exist to prevent. If a real second platform genuinely
needs the same thing, factor the shared *content* and keep only the per-platform
wiring — never a verbatim duplicate.
