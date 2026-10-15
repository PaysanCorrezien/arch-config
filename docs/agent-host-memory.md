# Memory budget for concurrent Brassens and Chirac agents

Both projects share the host's RAM, swap, compiler daemons and CPU. Agent
count alone is not a useful capacity limit: editing agents are much cheaper
than agents that each start a native build, Metro and an emulator.

## Defaults

- Temporary files use the private disk-backed `$HOME/.cache/devbox-tmp` through
  `TMPDIR`, `TMP` and `TEMP`. Zsh applies this to noninteractive agent commands;
  environment.d applies it to newly started systemd user services. Explicit
  per-lane values are preserved. Programs hardcoding `/tmp` need their own fix.
- Gradle uses a 4 GiB heap, up to four workers, a 1.5 GiB Kotlin daemon heap,
  the build cache, and a ten-minute idle timeout. Keep the pinned English JVM
  locale: changing it previously broke generated Kotlin.
- Cargo and CMake default to four compilation jobs. These are per invocation,
  not a shared host-wide semaphore. An explicit environment override wins.
- New tmux panes keep 20,000 history lines. Reloading this option does not
  trim existing panes; preserve their history before any manual cleanup.

User tmpfiles creates the temporary directory before `basic.target` at login;
the setup hook and Zsh also create it for an existing session. After applying
the dotfiles to an existing session, run
`systemd-tmpfiles --user --create ~/.config/user-tmpfiles.d/dev-build.conf`
before importing environment.d with `systemctl --user daemon-reload`.
New Zsh commands read `.zshenv` immediately. Existing processes retain their
environment and already running builds retain their JVM options. Do not
restart other agents' runtimes to make settings take effect.

## Admission and verification

On a 64 GiB host, start with one native Android build across both projects,
with other agents editing or running focused JS checks. Increase native build
concurrency only after measuring representative peak memory. An owned
emulator is still required for each simultaneous mobile acceptance lane;
lease it and stop only your own runtime when finished.

Check `free -h`, `swapon --show`, `cat /proc/pressure/memory`,
`cat /sys/block/zram0/mm_stat`, `df -h /tmp` and `vmstat 1 10`.
Swap occupancy alone does not prove current thrashing: look for sustained
swap-in/out and memory stalls while real commands run. Zram stores compressed
pages in physical RAM; its nominal swap capacity is not extra installed RAM.
Tmpfs files can be swapped and therefore contribute to the same pressure.

Keep emulator userdata, worktrees, databases, package stores and retained UAT
evidence on disk. Never clean `/tmp` wholesale or run `swapoff` under load.
For any migration, verify the source is inactive, copy it to SSD, checksum the
copy, preserve its original path if referenced, and retain unique state.
Do not commit snapshots containing account data or process environments.

The defaults trade maximum throughput of one isolated build for room to run
concurrent work. Validate a representative Android build in each project
before treating the smaller heap as accepted; the settings alone are not
build-performance proof.

Sources: [Linux tmpfs](https://docs.kernel.org/filesystems/tmpfs.html),
[Linux zram](https://docs.kernel.org/admin-guide/blockdev/zram.html), and
[Gradle build environment](https://docs.gradle.org/current/userguide/build_environment.html).
