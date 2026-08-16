# devbox migration — Windows host → Arch host + Windows guest

Moving the daily driver from bare-metal Windows to `hosts/devbox.yaml`: Arch/KDE
underneath, Windows 11 in KVM on top, Hermes on the host.

Export side is `windev-box/export-host-state.ps1`, run on the old machine before
it is wiped. This document is the import side.

---

## The decision to make first: where do repos live?

This is not a detail. Get it wrong and you spend a week debugging phantom build
failures.

The virtiofs share (`/srv/winshare` → `Z:`) **cannot hold git worktrees,
`node_modules`, or build trees.** Symlink and case-sensitivity semantics do not
match across it; pnpm's store is symlink-heavy; a tree checked out on one side
and built on the other fails in ways that look exactly like code bugs. This is
the same class of problem as the cross-linked worktree incident — an
inconsistency that typechecks and passes tests right up until it doesn't.

So each repo gets **one** native home:

| Work | Home | Why |
|---|---|---|
| Hermes + everything it drives | Arch host, `~/code` | Hermes is the reason for the move; its worktrees must be native POSIX |
| Backend, website, admin, mobile | Arch host | Nothing Windows-specific; agents work them directly |
| Brassens desktop (Electron + Rust UIA crates) | **Both**, as separate checkouts | The Windows UIA/sidecar crates only build and only validate on Windows |

For Brassens desktop: keep the host checkout as the one agents edit, and a
second independent checkout in the guest for Windows-native builds and UAT.
**Sync them through git — a branch and a push — never through the share.** It
feels like a detour and it is the only version that stays correct.

Consequence worth naming up front: Hermes on the host can no longer directly
drive a Windows-native build. Desktop UAT becomes an explicit guest-side step
rather than something the fleet does inline. That is a real capability loss and
the price of getting Hermes onto reliable ground.

---

## What actually moves

From the export bundle:

| Bundle path | Lands at | Notes |
|---|---|---|
| `hermes/` | `~/.hermes` | `%LOCALAPPDATA%\hermes` *is* `$HERMES_HOME`. Caches and `sandboxes/` are already stripped. |
| `hermes-desktop/connection.json` | reconfigure in-app | The rest of `%APPDATA%\Hermes` is Electron cache — dropped. |
| `claude/` | `~/.claude` | Per-project memory (`MEMORY.md` + its files) is the irreplaceable part. |
| `codex/` | `~/.codex` | Sessions excluded by default (~6 GB); `-IncludeCodexSessions` to keep them. |
| `ssh/` | `~/.ssh` | `chmod 600` on private keys after copying — Windows ACLs do not survive. |
| `secrets/` | `~/.secrets` | KeePassXC key file. `chmod 700` the directory. |
| `config/` | `~/.config` | Merge, do not overwrite — `dcli sync` owns much of this tree. |
| `keepassxc/` | `~/.config/keepassxc` | Different location on Linux. |
| `home-dotfiles/` | `~` | `.gitconfig` needs its identity checked — commits must be authored as PaysanCorrezien, not the agent bot. |

**Does not move.** Tailscale node identity (re-auth as a new node),
`%APPDATA%\Brassens` (app data, regenerates), anything under `D:\code`
(see below), Windows-native toolchains.

---

## Repos

The exporter writes `repos.md` rather than copying `D:\code`, on purpose:
working trees carry `node_modules`, `target/`, and Windows path semantics that
should not cross.

Before wiping, deal with what `repos.md` flags:

```bash
# anything listed as uncommitted or unpushed exists ONLY on that disk
```

Two known traps, both worth re-checking against `repos.md`:

- **Local `master` runs behind origin *and* carries unpushed commits.** A repo
  that looks clean on `git status` can still hold work that only exists locally.
  Check `@{u}..HEAD`, which is what the exporter reports.
- **`D:\code\.hermes-worktrees` and the various `*-worktrees` trees.** These are
  git worktrees whose administrative files point at absolute Windows paths.
  Do not copy them. Re-create worktrees on the new host from a fresh clone.

`_c-drive-salvage` is a leftover from the previous drive move. Confirm it holds
nothing unique, then let it die with the disk.

---

## Hermes path rewriting — the actual risk

The exporter writes `path-rewrites.md`. On this host that came back as **30
absolute paths in `cron/jobs.json`** plus **6 scripts** under `scripts/`.

These paths are not in `config.yaml`, so a config-level migration misses them
entirely. And a wrong path here does not fail loudly: a cron job silently
becomes a no-op, or a worktree root resolves to something that still exists but
is not what you meant. There is already a `jobs.json.bak-drive-move-20260814` in
the tree from the last time paths moved — that is what this failure mode looks
like.

Apply the mapping **before the first tick**:

```
D:\code\               ->  /home/dylan/code/
C:\Users\dylan\        ->  /home/dylan/
%LOCALAPPDATA%\hermes  ->  /home/dylan/.hermes
\                      ->  /
```

Then, with the gateway still stopped:

```bash
# no Windows-style path may remain anywhere in HERMES_HOME
grep -rEn '[A-Za-z]:\\|\\\\' ~/.hermes --include='*.json' --include='*.yaml' --include='*.py' \
  | grep -v '\.bak'
```

That must return nothing. Only then start the units:

```bash
systemctl --user enable --now hermes-gateway.service hermes-dashboard.service
```

Verify the first tick actually did work rather than merely exiting zero — check
`cron/ticker_last_success` advances and that a job with a rewritten path
produced real output.

---

## Order

1. **On the old host** — push every repo `repos.md` flags. Run
   `export-host-state.ps1 -Destination <encrypted volume>`. Read both reports.
2. **Verify the bundle opens** — mount it elsewhere, confirm the KeePassXC vault
   unlocks with the exported key file. Do this *before* wiping, not after.
3. **Install Arch/CachyOS**, bootstrap `arch-config`, set `host: devbox`,
   `dcli sync`. KDE + Hermes come up; `win-vm` defines the guest.
4. **Import** the bundle per the table above. Fix permissions (`chmod 600` keys,
   `700` on `~/.secrets`). Re-auth Tailscale as a new node.
5. **Rewrite Hermes paths**, run the grep, then start the units.
6. **Install Windows** in the guest (Pro — Home has no RDP server), run
   `windev-box/bootstrap.ps1`, then `windev-box/setup-vm-guest.ps1`.
7. **Re-clone** the Brassens repo inside the guest for Windows-native builds.
8. **Validate the two assumptions the whole design rests on**: audio fidelity
   through USB passthrough, and UIA/focus tracking under an RDP session.

Step 8 is the one to not skip. Both are cheap to test and expensive to discover
after the old disk is gone.

---

## Keep the old disk

The 120 GB SATA SSD is currently a Windows disk. Do not reuse it in the new
build until the migration has run for a week. It is the only rollback that
exists — a bundle that turns out to be missing something is recoverable while
the original filesystem is still intact, and not afterwards.
