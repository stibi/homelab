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
4. Stows the `zsh-linux-zase-prace-vm` package into `$HOME`.
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
SSH. Note that `shell_stow_package` is host-specific — a new machine wants its
own stow package in the dotfiles repo rather than reusing zase-prace's.

## Notes

- `neovim` is intentionally left out of the apt package list on zase-prace:
  a newer upstream build already lives in `/opt/nvim-linux-x86_64`, and the
  apt package would shadow it in `/usr/bin`.
- `zsh-completions` is not packaged in Debian 13. zsh 5.9 ships a large
  completion set in `/usr/share/zsh/vendor-completions` already.
