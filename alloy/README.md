# alloy/

Probes for Alloy 6 (the version with the temporal `var` /
`always` / `eventually` extension).

## Install

```sh
# macOS
brew install alloy

# Nix
nix run nixpkgs#alloy
```

## Run

Each `.als` file lists its own commands in the top comment.
Two run styles:

```sh
# headless: enumerate counterexamples / instances on the CLI
alloy execute --command <CommandName> app-rbac.als

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
