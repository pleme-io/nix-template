# pleme-io/nix-template

A **public, worked example** of a pleme-io-style Nix fleet repo — cast from the
**kata** mold (型, "the standard form"). It's filled with the patterns and a
small example fleet, and contains **nothing private**: every node name, domain,
user, and key here is a placeholder. Copy it, replace the example facts with
yours, and you have a fleet.

> This is the rich example. The minimal upstream template is
> `nix flake init -t github:pleme-io/substrate#fleet`.

## The idea

A fleet repo is **private configuration over a shared, typed vocabulary.** You
write your fleet's *facts* once in `fleet.nix`; the vocabulary mechanically
derives every system from them.

```
fleet.nix (you)  ->  kata (fleet shape: mkFleet, the blanks schema)
                  ->  iroha (composition alphabet)
                  ->  blackmatter (component behavior)
                  ->  nixpkgs module system
```

`nix eval .#fleetReport --json` shows the whole fleet derived from one call.

## What's in here

| Surface | File | Yours / generic |
|---|---|---|
| **The blanks** | `fleet.nix` | **YOURS** — name, domains, users, trust keys, nodes, apps, vpnLinks, secrets backend |
| Profile catalog | `lib/profiles.nix` | the single name→module interface (pattern) |
| Profiles | `profiles/*.nix` | thin enable-flips (example; mostly generic) |
| Typed-enum pattern | `modules/node-mode.nix` | reusable as-is |
| Node hardware | `nodes/<host>/` | **YOURS** — `hardware-configuration.nix` per host (placeholders here) |
| Secrets | `secrets.example.yaml` + `.sops.yaml` | **YOURS** — SOPS/age (the real `secrets.yaml` is gitignored) |
| Patterns | `docs/PATTERNS.md` | the architecture explained |

Everything *behavioral* — option surfaces, components, daemons, overlays,
manifests, host assembly, deploy data, checks — comes from the vocabulary
(flake inputs), never hand-rolled here.

## Use it

```sh
# 1. copy this repo (or `nix flake init -t github:pleme-io/nix-template`)
# 2. edit fleet.nix      — your name, domains, users, nodes
# 3. fill nodes/<host>/hardware-configuration.nix  (from `nixos-generate-config`)
# 4. cp secrets.example.yaml secrets.yaml && sops secrets.yaml   # real secrets
# 5. set your age recipient in .sops.yaml
nix eval .#fleetReport --json | jq      # the derived fleet
nix flake check                          # the invariant suite (typed gates)
nixos-rebuild switch --flake .#server-01 --target-host root@<host>
```

## Going richer (the pleme-io way)

The example profiles use plain nixpkgs options so this repo evaluates standalone.
A real fleet adds the behavior vocabulary as flake inputs and consumes it in the
profiles:

```nix
# flake.nix inputs
blackmatter.url = "github:pleme-io/blackmatter";
# profiles/server-base.nix
blackmatter.components.sshServer.enable = lib.mkDefault true;
```

The comments in each `profiles/*.nix` show the blackmatter line they stand in for.

## The gate

`checks` is *declared* by every fleet flake — but nothing in the fleet workflow
ever **builds** it. `nixos-rebuild` / `darwin-rebuild` never look at `checks`,
and a fleet repo is private by default, so no CI runs `nix flake check`. A
declared-but-uninvoked check is not a weak gate; it is **nothing at all**.

So the invariant verdict is forced where the rebuild cannot route around it. The
18 kata invariants are decided at *eval* time, and `flake.nix` `seq`s that
verdict onto every **shipping** output (`nixosConfigurations`,
`darwinConfigurations`, `fleetDeploy`, `fleetRegistry`):

```
$ nixos-rebuild switch --flake .#server-01     # after a duplicate uid in fleet.nix
error: fleet gate: FAILED — 16/18 passed invariants
  FAIL test:users:gids-unique
    expected: true
    got:      false
  FAIL test:users:uids-unique
    expected: true
    got:      false
```

No CI, no builder, no matching system needed — it throws before one byte is
built. The **diagnostic** outputs (`fleetReport`, `profileCatalog`, `checks`)
are deliberately *ungated*, so a fleet whose gate is red can still be inspected.
The gate also refuses to be green over an **empty** invariant suite: a gate with
no subjects proves nothing while looking like the strongest kind of evidence.

**Tier: eval-rejected.** Stronger than a CI gate (`only-mitigated`, and vacuous
in a private repo where Actions never run); weaker than truly-unrepresentable —
a Nix `throw` is not a compile error.

*If your fleet repo is **public***, add CI on top — the gate is the floor, not a
reason to skip it. Use the non-empty-set pattern from
`substrate/.github/workflows/cargo-ci.yml` (`flakeChecksGatePath`), which fails
rather than reporting green over zero checks; a bare `nix flake check` step is
green on a flake that declares none.

## Rules

1. **Never write behavior modules here.** Extend the vocabulary, then consume it.
2. Every host is one `nodes.<name>` entry in `fleet.nix` + one `nodes/<name>/` dir.
3. Every app is one `apps.<name>` manifest entry.
4. A schema typo in `fleet.nix` **fails evaluation with a named error** — unknown
   keys are rejected, never ignored — and a broken *invariant* fails the same way,
   at rebuild time, via the gate above.

See [`docs/PATTERNS.md`](docs/PATTERNS.md) for the patterns (the blanks, thin
profiles, the catalog, the typed-enum, the manifest) and why they're shaped this
way.
