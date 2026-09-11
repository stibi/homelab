# homelab

Ansible for setting up and personalising my machines.

Right now that means one host — **zase-prace**, the Debian 13 work VM — but
the layout is inventory-based so the other Debian boxes can be added without
restructuring anything.

## Layout

```
ansible.cfg                       points at the inventory, sane defaults
inventory/
  hosts.yml                       zase-prace (managed locally)
  group_vars/workstations.yml     package lists, dotfiles settings
playbooks/workstation.yml         base + shell
roles/
  base/                           apt packages every box should have
  shell/                          zsh, starship, plugins, dotfiles via stow
  kubernetes/                     kubectl + kubie, kubeconfig layout
  talos/                          talosctl + omnictl
  asdf/                           asdf plugins and pinned versions (pre-commit)
  cli_tools/                      gh, glab, cue, flux from release tarballs
  codex/                          OpenAI Codex CLI
  krr/                            Robusta KRR (PyInstaller bundle)
  hunk/                           hunk, compiled from source (CPU has no AVX2)
  herdr/                          herdr binary (does NOT restart the server)
  worktrunk/                      Worktrunk (`wt` and `git wt`)
  onepassword/                    1Password CLI from the vendor's signed apt repo
  vault/                          HashiCorp Vault CLI from its release archive
  awscli/                         AWS CLI v2, PGP-signature verified
  node_exporter/                  Prometheus node_exporter, bound to Tailscale
Makefile                          check / apply wrappers
```

## Usage

```sh
make deps      # one-off: install ansible-core
make lint      # syntax check
make check     # dry run with a diff of what would change
make apply     # do it
make shell     # only the shell role
```

Target a single host or role when iterating:

```sh
make apply LIMIT=zase-prace TAGS=shell
```

## What the shell role does

1. Installs zsh, starship, stow and the CLI tooling the shell config expects
   (fzf, ripgrep, fd-find, zoxide, eza, bat, git-delta, direnv, plus the
   zsh autosuggestions / syntax-highlighting plugins).
2. Clones [dotfiles](https://github.com/stibi/dotfiles) if it is missing —
   it never pulls, so local edits are safe.
3. Moves any pre-existing real `~/.zshrc`, `~/.zshrc.d` or
   `~/.config/starship.toml` aside with a `.pre-stow.<timestamp>` suffix.
4. Stows the packages in `shell_stow_packages` into `$HOME` —
   `zsh-linux-zase-prace-vm` (machine-specific) and `nvim` (shared with the
   macOS workstation, nothing platform-dependent in it).
5. Sets the login shell to `/usr/bin/zsh`.
6. Starts an interactive zsh as a smoke test, so a broken config fails the
   run instead of ambushing you at next login.

The shell configuration itself lives in the dotfiles repo, not here — this
repo only installs and wires it up.

## Kubeconfig layout

One file per cluster, never one big `~/.kube/config`:

```
~/.kube/
  kubie.yaml      symlink from the dotfiles package
  config          scratch file — absorbs stray `kubectl config` writes
  configs/        0700, one file per cluster, NOT in git
    prod.yaml
    staging.yaml
```

Adding a cluster is just dropping its kubeconfig into `~/.kube/configs/`.
Nothing needs to be merged or re-run.

**kubie** is the primary interface. `kubie ctx` opens a subshell with its own
isolated `KUBECONFIG`, so two terminals can sit on two different clusters at
once — which plain `kubectl config use-context` cannot do, since it mutates
state shared by every shell. kubie never writes to your cluster files.

```sh
kubie ctx              # pick a context, spawns a subshell
kubie ns               # pick a namespace within it
kubie exec prod app -- kubectl get pods    # one-off, no subshell
exit                   # leave the context
```

As a fallback, `.zshrc.d/55-kubernetes.zsh` also builds a merged `KUBECONFIG`
from the same directory, so a bare `kubectl` outside a kubie shell still sees
every cluster. `~/.kube/config` is first in that list on purpose, so anything
that does write goes there rather than into a real cluster file.

Cluster files stay out of version control — they hold credentials. The role
only creates the directory (`0700`) and the empty scratch config (`0600`).

## Upgrading kubectl

kubectl is installed as a pinned, checksum-verified binary from `dl.k8s.io`.
Neither package source can supply the current release: Debian 13 ships 1.32.3,
and the official Kubernetes apt repo for v1.36 only carries 1.36.0-1.1.

To bump it, read the new version and its checksum, then update both values in
`inventory/group_vars/workstations.yml`:

```sh
V=$(curl -sL https://dl.k8s.io/release/stable.txt) && echo "$V"
curl -sL "https://dl.k8s.io/release/$V/bin/linux/amd64/kubectl.sha256"
```

They are pinned rather than fetched at run time on purpose — fetching the
checksum from the same place as the binary would verify nothing. Pinning them
in git is what makes the download meaningful and the build reproducible.

## Upgrading the CLI tools (gh, glab, cue, flux)

All four are pinned release tarballs in the `cli_tools` list in
`inventory/group_vars/workstations.yml`.

```sh
make cli-latest
```

That prints current versions and checksums for all four. Paste them in, along
with the version inside `url` and `archive_path`.

Things that bite when bumping these:

- **Each tool lays its tarball out differently**, which is what `archive_path`
  records: `gh` nests under a versioned directory, `glab` under `bin/`, `cue`
  and `flux` put the binary at the archive root. `gh`'s path contains the
  version, so it must be bumped in two places.
- **`cue` publishes no checksums file** — its sha256 has to be computed by
  hand (`make cli-latest` prints the command). It is also the only one whose
  tarball name carries a `v` prefix.
- **`cue` has no `--version` flag**; it is `cue version`. That is why
  `version_args` is per-tool.
- `gh`, `glab` and `flux` are pinned for amd64 and arm64; `cue` is amd64 only.

Both `gh` and `glab` exist in Debian 13, but lag badly — 2.46.0 vs 2.97.0 and
1.53.0 vs 1.113.0 — which is why they come from upstream releases instead.

## 1Password CLI

Installed from 1Password's own signed apt repository, which is a deliberate
departure from how other CLI tools here are handled. `op` hands out
credentials, so authenticating the binary matters more than consistency:

| route | verification |
|---|---|
| asdf plugin (`NeoHsu/asdf-1password-cli`) | none — downloads a zip and unzips it |
| pinned `get_url` | trust-on-first-use; the checksum would be ours, not upstream's |
| **vendor apt repo** | **GPG-signed, verified by apt on every package and upgrade** |

`deb822_repository` takes the key URL directly and dearmors it itself, so there
is no separate key step and no use of the deprecated `apt_key` module.

The version is not pinned, matching every other apt package here — a security
tool tracking the vendor's stable channel beats reproducing an old build.

**On a headless host `op` cannot use desktop-app or biometric unlock.** Use a
service account token (`OP_SERVICE_ACCOUNT_TOKEN`) for non-interactive access,
or `op signin` for an interactive session.

## AWS CLI

Installed from AWS's own installer with its detached PGP signature verified,
rather than from apt. Debian 13 does package awscli v2, but carries 2.23.6
against 2.36.36 upstream — roughly a year of AWS service coverage, which
matters on a box driving EKS daily.

Verification follows the same reasoning as the 1Password CLI: this tool holds
production AWS credentials, so the download needs a real chain of trust rather
than a checksum computed here. The signing key is committed in
`roles/awscli/files/aws-cli.asc` and its fingerprint is asserted after import,
so a tampered key file cannot quietly validate a tampered installer.

The role also creates `~/.aws/` (0700) with empty `config` and `credentials`
files (0600), so they exist with tight permissions from the start rather than
being written later under whatever umask applies. Content is never managed:
`copy` runs with `force: false`, so a re-run cannot wipe real credentials. A
separate `file` task enforces the mode, because `copy` with `force: false`
skips an existing file entirely and leaves its permissions alone — a 0644
credentials file would otherwise silently stay 0644.

Bump `awscli_version` to upgrade; the role passes `--update` to the bundled
installer when an install already exists.

```sh
curl -sSL 'https://api.github.com/repos/aws/aws-cli/tags?per_page=20' \
  | jq -r '.[].name' | grep -E '^2\.' | head -1
```

## Vault CLI

Vault is installed as a pinned release archive in `~/.local/bin`, verified
against the SHA256SUMS published by HashiCorp. The archive route is deliberate:
the vendor apt package also creates a `vault` system user, server configuration
and a systemd unit, none of which is needed on a CLI-only workstation.

To upgrade, find the current version and update `vault_version` plus both
entries in `vault_sha256`:

```sh
V=$(curl -sL https://developer.hashicorp.com/vault/install \
  | sed -n 's/.*Vault Version: \([0-9.]*\).*/\1/p' | head -1)
echo "$V"
curl -sL "https://releases.hashicorp.com/vault/$V/vault_${V}_SHA256SUMS" \
  | grep -E "vault_${V}_linux_(amd64|arm64)\\.zip$"
```

## herdr

Bump `herdr_version` and its `herdr_sha256` entry in
`inventory/group_vars/workstations.yml`. Upstream publishes no checksum file,
so compute it:

```sh
curl -sL https://github.com/herdrdev/herdr/releases/download/v<VER>/herdr-linux-x86_64 | sha256sum
```

**The role only replaces the binary on disk.** It does not stop, restart or
hand off a running server, because that kills every pane process in the
session — including any agent running in one. After applying, `herdr status`
will report a client/server version skew until you restart it yourself:

| Action | Layout | Pane processes / agents |
|---|---|---|
| `herdr update --handoff` | kept | **kept** (experimental live handoff) |
| `herdr server stop`, then relaunch | restored from `session.json` | **lost** |
| Machine reboot | restored from `session.json` | **lost** |
| Detach (`prefix q`) | kept | kept — server keeps running |

Config-only changes need no restart at all: `herdr server reload-config`
re-reads `config.toml` in place.

herdr also ships its own updater (`herdr update`, `herdr channel`). That and
this role are two sources of truth for the same file — a self-update installs
whatever the channel offers, and the next Ansible run pins it back. Use one or
the other. Managing it here is the choice consistent with the rest of this
repo; if you prefer the built-in updater, delete this role rather than letting
them fight.

## Upgrading Worktrunk

Worktrunk is installed from its static musl release archive into a versioned
directory, with both `wt` and `git-wt` linked into `~/.local/bin`. The checksum
is published upstream in the release's `sha256.sum`. Worktrunk requires Git
2.43 or newer; Debian 13's Git satisfies that requirement.

The zsh integration is declared in the dotfiles repo instead of running
`wt config shell install`, because that command edits `.zshrc` itself. The
integration is required for commands such as `wt switch` to change the parent
shell's working directory.

To upgrade, update `worktrunk_version` and both checksum entries in
`inventory/group_vars/workstations.yml`:

```sh
V=$(curl -sL https://api.github.com/repos/max-sixty/worktrunk/releases/latest \
  | jq -r '.tag_name')
echo "$V"
curl -sL "https://github.com/max-sixty/worktrunk/releases/download/$V/sha256.sum" \
  | grep -E 'worktrunk-(x86_64|aarch64)-unknown-linux-musl\.tar\.xz$'
```

## hunk — why it is compiled, not downloaded

Bump `hunk_version` in `inventory/group_vars/workstations.yml` and re-run. The
role checks out that git tag, builds, and installs. There is no checksum to
pin because the artifact is produced locally.

**Do not "simplify" this into a `get_url` of the release tarball.** This host
is a Xeon E5-2680 v2 (Ivy Bridge): it has AVX but **no AVX2**, and upstream's
prebuilt `hunkdiff-linux-x64` binary dies immediately with `SIGILL` (exit 132).
That is the physical silicon, so no Proxmox CPU-model change fixes it.

Building locally works because of one specific link in the chain: the `bun` npm
package's postinstall reads `/proc/cpuinfo`, sees no `avx2`, and fetches the
**`bun-linux-x64-baseline`** runtime, which `bun build --compile` then embeds.
The result reports `Bun v1.3.14 (Linux x64 baseline)` and runs.

Two non-obvious details the role depends on:

- Dependencies install with `--ignore-scripts`, because the root package's
  `prepare` hook runs `simple-git-hooks`, which fails outside a normal dev
  checkout and aborts the whole install. That also skips bun's own postinstall,
  so the role runs `node node_modules/bun/install.js` explicitly — that is the
  step that selects the baseline runtime, and skipping it produces a binary
  that SIGILLs exactly like the prebuilt one.
- The binary is installed to `~/.local/share/hunk/<version>/` with its skills
  beside it and symlinked to `~/.local/bin/hunk`. `hunk skill path` resolves
  skills relative to the *resolved* binary, so they must sit next to the real
  file, not next to the symlink.

The build tree (~460M of node_modules plus a 161M binary) is removed after a
successful install; set `hunk_keep_build_dir: true` to keep it.

Requires `bun` and `node`, both of which come from the hand-managed asdf
install on this host.

## Upgrading krr

```sh
V=$(curl -sL https://api.github.com/repos/robusta-dev/krr/releases/latest \
    | sed -n 's/.*"tag_name": "v\([^"]*\)".*/\1/p') && echo "$V"
curl -sL "https://github.com/robusta-dev/krr/releases/download/v$V/krr-ubuntu-latest-v$V.zip" | sha256sum
```

krr publishes no checksum file, so its sha256 has to be computed by hand.

Like codex, it is not a lone binary: the zip holds a PyInstaller *onedir*
bundle (`krr/krr` beside a `krr/_internal/` tree with a bundled CPython), so it
unpacks whole into `~/.local/share/krr/<version>/` and is symlinked onto PATH.
The bundle runs correctly through that symlink — PyInstaller resolves the
executable's real path — and the `ubuntu-latest` build runs fine on Debian 13.

Two gotchas: the asset is named after the GitHub runner (`ubuntu-latest`) not
an architecture, and there is **no arm64 linux build** — the role asserts on
non-x86_64. Its version subcommand is `krr version`, not `--version`.

## node_exporter

Installed from the Debian package rather than an upstream binary. Debian 13
carries 1.9.0 against 1.12.1 upstream, but the package brings a dedicated
`prometheus` user, a hardened systemd unit and an `EnvironmentFile` for
arguments — worth more here than the version delta.

**It binds the host's Tailscale address, not `0.0.0.0`.** This host has no
active firewall (`INPUT` policy is `ACCEPT`; only Tailscale's and Docker's own
chains exist), so listening on all interfaces would serve machine metrics to
the home LAN too. The point of running it is to be scraped over Tailscale, so
it listens there and nowhere else. A systemd drop-in orders it after
`tailscaled` so the address exists before it tries to bind.

To listen everywhere instead, set in `group_vars`:

```yaml
node_exporter_bind_tailscale: false
node_exporter_listen_address: "0.0.0.0"
```

The role prints the resulting scrape target at the end of a run, and probes
`/metrics` to confirm the service actually came up.

## Upgrading codex

Set `codex_version` and the matching `codex_sha256` entry in
`inventory/group_vars/workstations.yml`:

```sh
V=$(curl -sL https://api.github.com/repos/openai/codex/releases/latest \
    | sed -n 's/.*"tag_name": "rust-v\([^"]*\)".*/\1/p') && echo "$V"
curl -sL "https://github.com/openai/codex/releases/download/rust-v$V/codex-package_SHA256SUMS" \
  | grep -E '  codex-package-(x86_64|aarch64)-unknown-linux-musl'
```

Note the upstream tag is `rust-vX.Y.Z` while the version is `X.Y.Z`, and that
artifacts are named with Rust target triples rather than amd64/arm64.

The two leading spaces in that grep are load-bearing. Since 0.152.1 the sums
file also lists `codex-app-server-package-*` for the same target triples, and
a looser pattern matches those too — anchoring on the separator that precedes
the filename is what keeps `codex-package-` distinct from a suffix match.

codex installs differently from the other CLI tools. It is unpacked whole into
`~/.local/share/codex/<version>/` and symlinked to `~/.local/bin/codex`,
because the release is not a lone binary — it bundles a ripgrep, a `bwrap`
sandbox and zsh resources that codex expects beside itself. It is also large:
~119M compressed, ~300M unpacked. Only the `-package-` artifacts have
published checksums, which is the other reason that variant is used.

Old versions are left in `~/.local/share/codex/` on a bump; remove them by hand.

## asdf-managed tools

asdf is hand-installed and already manages nodejs and bun. The `asdf` role
does **not** install or touch asdf itself — it only adds plugins and pins
versions listed in `asdf_tools`, so the existing entries are left alone.

The managed tools include **pre-commit** and the development toolchains listed
in `asdf_tools`. The pre-commit plugin installs its official `.pyz` zipapp from
the GitHub release, so no pip or system Python packaging is involved; the
zipapp runs under `python3` directly.

Rust is installed with the `code-lever/asdf-rust` plugin, which uses the
official Rust distribution. Its default profile supplies `rustc`, `cargo`,
`rustfmt` and `clippy`; `build-essential`, `pkg-config` and `libssl-dev` come
from apt for crates that compile or link native dependencies.

`~/.tool-versions` is edited with `lineinfile` rather than `asdf set --home`.
The file carries hand-written entries — including `nodejs lts`, an alias
rather than a concrete version — and rewriting it through asdf risks
normalising those. This way only the managed line is touched.

Note that asdf plugins fetch without checksum verification, unlike the pinned
binaries in the `kubernetes` and `talos` roles. That is inherent to asdf.

**`python3-venv` is a hard requirement**, and is in `base_packages` for this
reason: Debian splits venv out of the stdlib, so `python3 -m venv` fails
without it. pre-commit builds a virtualenv for every `language: python` hook,
so without it pre-commit installs cleanly and then breaks on first real use.

## Upgrading talosctl / omnictl

Both live in the `talos_binaries` list in
`inventory/group_vars/workstations.yml`, pinned per architecture. Unlike
kubie, Sidero publish a `sha256sum.txt` with every release, so these are
upstream's own checksums.

```sh
make talos-latest
```

That prints the current tag and the linux checksums for both projects; paste
them into the list. Bear in mind **omnictl should track the Omni instance you
connect to** — taking the newest release is not automatically right if your
Omni backend is older.

## Adding another host

Add it under `workstations` in `inventory/hosts.yml`; it will be reached over
SSH. Note that the first entry of `shell_stow_packages` is host-specific — a
new machine wants its own stow package in the dotfiles repo rather than reusing
zase-prace's. Portable packages such as `nvim` can be shared as-is.

## Notes

- `neovim` is intentionally left out of the apt package list on zase-prace:
  a newer upstream build already lives in `/opt/nvim-linux-x86_64`, and the
  apt package would shadow it in `/usr/bin`.
- `zsh-completions` is not packaged in Debian 13. zsh 5.9 ships a large
  completion set in `/usr/share/zsh/vendor-completions` already.
