# languages/alloy/

Probes for Alloy 6 (the version with the temporal `var` /
`always` / `eventually` extension).

## Install

```sh
# Repo-local (recommended)
cd /path/to/formal-methods-playground
nix develop      # devShell brings alloy6, tlc, dafny, coqc, elan, z3, cvc5

# Or globally via nix
nix profile install nixpkgs#alloy6
```

## Run

Each `.als` file lists its own commands in the top comment.
Two run styles:

```sh
# headless: enumerate counterexamples / instances on the CLI
alloy6 exec --command <CommandName> app-rbac.als

# GUI: interactive theorem exploration + instance visualiser
alloy
# then File → Open → app-rbac.als, pick a command from the
# Execute menu.
```

The GUI is worth keeping open while authoring — the instance
visualiser is half of what makes Alloy itself the value
proposition.

## Probes

| File | Topic |
| --- | --- |
| [`app-rbac.als`](app-rbac.als) | RBAC + screen-navigation safety + sanity check |
