# Renovate — design notes

Status: **designed, not implemented.** Nothing in this repo runs Renovate yet.
This captures the research so it does not have to be redone.

The goal is to automate what is currently manual: noticing a new upstream
release, finding its checksum, and editing `inventory/group_vars/workstations.yml`.

## It has to be self-hosted (GitHub Action), not the Mend app

The obvious choice is the Mend-hosted Renovate app — no infrastructure. It does
not work here, for one reason:

**Renovate cannot update the `sha256` values.** It has no idea what the checksum
of a release artifact is. `currentDigest` exists, but only for container image
digests, where the datasource supplies it. Updating arbitrary release-artifact
sums alongside a version is a [long-standing feature request][sha-request], not
a feature.

So a bare version bump produces a PR that is *guaranteed* broken — `get_url`
fails the checksum every time. The fix is `postUpgradeTasks`, running a script
that recomputes the sums. The `allowedCommands` option that gates it is
[self-hosted only][allowed-commands].

Running Renovate via `renovatebot/github-action` **is** self-hosting, so that
path is open and the hosted app's is not. This is the decisive constraint;
everything else follows from it.

[sha-request]: https://github.com/renovatebot/renovate/discussions/22183
[allowed-commands]: https://docs.renovatebot.com/self-hosted-configuration/#allowedcommands

## Prerequisites

- The repo must be pushed. As of 2026-09-04 `main` is **20 commits ahead of
  `origin/main`** and `gh` is not authenticated here, so the remote state of
  `git@github.com:stibi/homelab.git` is unconfirmed — including whether it
  exists and whether it is private.
- Re-run the confidentiality check before pushing. The earlier audit covered
  this repo at roughly commit 18 and found it clean; the finding was in
  *dotfiles* (`zsh/bin/fzf-workflows.zsh`), not here. Commits since are version
  pins and README prose, so it is very likely still clean — but `inventory/`
  is the place to look, for anything describing the on-prem network.

## The work

### 1. Custom regex managers

Renovate has no native understanding of this repo: no `.tool-versions`, no
lockfile, just hand-rolled Ansible YAML. Every pin needs a `customManagers`
entry. There are two shapes, ~18 tools:

- **flat scalars** — `kubectl_version`, `kubie_version`, `codex_version`,
  `krr_version`, `hunk_version`, `awscli_version`, `herdr_version`
- **list items** under `cli_tools:` / `talos:` / `asdf_tools:` —
  `- name: gh` followed by `version: 2.97.0`

The second shape is the fiddly one. The regex has to bind a `name:` to the
`version:` a line or two below it, and Renovate matches **per-file, not
per-line**, so a greedy pattern will happily pair one tool's name with another
tool's version. Worth validating against the real file rather than a fixture.

### 2. Datasources

Mostly `github-releases` against the slugs already present in the roles:

| tool | source |
| --- | --- |
| gh | `cli/cli` |
| cue | `cue-lang/cue` |
| k9s | `derailed/k9s` |
| flux | `fluxcd/flux2` |
| herdr | `herdrdev/herdr` |
| kubie | `kubie-org/kubie` |
| codex | `openai/codex` |
| krr | `robusta-dev/krr` |
| hunk | `modem-dev/hunk` |
| talosctl | `siderolabs/talos` |
| omnictl | `siderolabs/omni` |

Three exceptions:

- **kubectl** — `github-tags` on `kubernetes/kubernetes`; the role downloads
  from `dl.k8s.io`, which mirrors the tag.
- **glab** — not on GitHub. `gitlab-releases` datasource, `gitlab-org/cli`.
- **awscli** — `github-tags` on `aws/aws-cli`.

**codex needs `extractVersion`** to strip its `rust-v` tag prefix: the upstream
tag is `rust-v0.152.1` while the pin is `0.152.1`.

### 3. A checksum-refresh script

`scripts/refresh-checksums.sh <tool>`, wired to `postUpgradeTasks`. For tools
publishing a `SHA256SUMS` it fetches and greps it; for the rest it downloads the
artifact and computes. This is the only genuinely new code the design needs.

Note the codex artifacts are ~119 MB compressed per architecture, and the sums
file lists `codex-app-server-package-*` alongside `codex-package-*` for the same
target triples — the script must anchor on the filename, not just the triple.
See "Upgrading codex" in the README.

### 4. The workflow

`.github/workflows/renovate.yml`, scheduled, with a token in secrets.
`GITHUB_TOKEN` works, but PRs it opens will not trigger other workflows; a PAT
or GitHub App token avoids that.

## Decision still open: the trust-on-first-use tools

Four tools — **kubie, cue, krr, herdr** — publish no upstream checksums. The
comments in `workstations.yml` are explicit that those sums were computed once,
by hand, and pinned from then on.

If the refresh script recomputes them automatically, **the pin stops attesting
anything.** It becomes a record of whatever CI happened to download that
morning, which a compromised release would pass trivially. The TOFU property
depends on a human having looked once.

Two honest options:

1. **Exclude those four** from Renovate and keep bumping them by hand.
2. Accept that they become convenience pins, and stop describing them as a
   security control in the comments.

Recommendation was (1) — it is four tools, they update rarely, and it preserves
the distinction the existing comments already draw. Not yet agreed.

The other eleven publish real upstream sums, so automating those loses nothing.

## What Renovate will not do

A PR cannot tell you the new version *works*. The roles assert version equality
against a real host at apply time, and CI has no equivalent — there is no host
to apply to. `make lint` (syntax-check) in CI is the realistic ceiling.

Renovate removes the "check for updates, find the checksum, edit YAML" chore.
It does not remove applying and verifying, which stays manual.

One asymmetry worth remembering: **a `hunk` bump means a source compile on
apply, not a download.** Its PRs are cheap to merge and expensive to apply.
