# Working in this repo

Ansible that provisions and personalises workstation-class hosts. Today that is
one host: `zase-prace`, a Debian 13 work VM, managed **from itself** over
`ansible_connection: local`.

Read `README.md` first — it carries per-tool upgrade recipes (kubectl, codex,
herdr, hunk and others), and those recipes encode real gotchas.

## The one rule that matters

**Build it, dry-run it, then stop.** Stibi runs the mutating step himself after
reviewing the diff. `make check` and read-only inspection are fine unprompted;
`make apply` is not, unless he has asked for that specific thing to be applied
in that message.

This is not ceremony. The playbook installs into a live daily-driver machine,
and several roles are slow or awkward to undo.

```sh
make lint     # syntax-check only
make check    # dry run, --check --diff
make apply    # ask first
make check TAGS=<role>   # scope to one role
```

## Layout

- `inventory/group_vars/workstations.yml` — **every version pin lives here.**
  Roles carry no versions of their own; `defaults/main.yml` holds empty strings
  and the role asserts on a missing pin rather than silently building a bad URL.
- `roles/` — one per tool or concern.
- `playbooks/workstation.yml` — role order and tags.
- `docs/renovate.md` — design notes for automating the version bumps. Not
  implemented.

## Conventions worth not breaking

**Comments are load-bearing.** Several explain why an obvious simplification is
wrong. The `hunk` role compiles from source and says so at the top; that is
because this CPU (Xeon E5-2680 v2, Ivy Bridge) has AVX but **not AVX2**, and
upstream's prebuilt binaries die with SIGILL. Do not "simplify" it into a
`get_url` of the release tarball. Similar notes sit on the stow invocation, the
awscli config-permissions tasks, and the codex checksum recipe.

**Check-mode guards.** Many tasks carry `when: not ansible_check_mode`. They are
there because a later task would otherwise fail against state an earlier,
simulated task did not actually create. Removing them breaks `make check`.

**Verification tiers for downloads.** Roughly, in descending order of trust:
vendor PGP signature (awscli, onepassword) → upstream-published checksum
(kubectl, gh, glab, flux, k9s, talosctl, omnictl) → checksum computed once by
hand and pinned from then on, trust-on-first-use (kubie, cue, krr, herdr). The
comments say which is which. That distinction is deliberate — see the open
question in `docs/renovate.md` before automating any of it away.

**Idempotency is expected.** A second `make apply` should report `changed=0`.
If a role cannot manage that, say so rather than leaving it noisy.

## Dotfiles are a separate repo

`~/dev/moje/dotfiles`, stowed from here by the `shell` role. Ansible installs
software; dotfiles configure it. Shell config for this host lives in the
`zsh-linux-zase-prace-vm` stow package — deliberately machine-specific, not
portable.

**`stow --no-folding` is not optional.** Without it stow folds directories, and
`~/.kube` would become a symlink into the dotfiles repo — putting cluster
credentials inside a git working tree. The comment on that task explains it.

## State as of 2026-09-04

`main` is ahead of `origin/main` and has never been pushed; `gh` is not
authenticated on this host, so the remote's existence and visibility are
unconfirmed. Anything depending on CI, or on Renovate, is blocked on that.
