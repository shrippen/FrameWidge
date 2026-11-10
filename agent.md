# Working rules for this repository

The rules for all shrippen repositories are in `RULES.md` (writing, code, commits, bug
fixes, repository, GUI). It is a synced copy from the rules repository; do not edit it
here. This file holds only what is particular to this repository. A Claude Code session on
the owner's machine has the rules through the global `CLAUDE.md` already and reads
`RULES.md` only for its GUI rule, before work on a user interface.

## GUI (this project)

- Here: `package/contents/ui/Kante` and `package/contents/ui/KantePlasma` are copied from
  Kante by `scripts/sync-kante.sh`; never edit them. The landing page links
  `https://shrippen.github.io/v1/`.

## Release

Release steps: `RELEASE.md`. Before a release, load the skill `release-changelog`. A release
is published, so the owner confirms it in words.

## Repository (this project)

- CI runs on the GitHub mirror (`.github/workflows/ci.yml`, since 16.10.2026) and reports back to Gitea as the commit status `github / test`.
- The merge waits for: CI is green: the newest `github / test` status on the PR's latest commit is success. `ci.yml` runs on every push (no path filter), so every PR waits for it; no status yet means wait, not merge. PR-Agent's status does not count here.
- The owner also confirms: `.gitea/pr-agent/`, what runs as root on users' machines (the service `service/` with its code, unit, D-Bus policy and polkit action, `install.sh`, `uninstall.sh`), the landing page `docs/`, the KDE Store text.
- Everything else: `RULES.md` (Repository) and the skill `pr-review`.
