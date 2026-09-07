# Hermes automation migration

Status as of 2026-09-08: the specialist-profile cutover is live. Each enabled
job has one owner as declared by `profile-cron-split.yaml`; the default profile
retains only the separate STT critical-review job. Profile scripts are copied
from the preserved `~/.hermes/scripts` runtime by the module's reliability
reconciler and validated before gateway restart.

The gateway's built-in scheduler is the appropriate executor.  It persists
jobs under each profile's `cron/jobs.json`; it does not need a systemd timer.
The dashboard API can manage those jobs when an authenticated user is present.
The separate OpenAI-compatible API server is intentionally disabled until a
specific machine client needs it and has a bearer-key lifecycle.

## Service policy

- `hermes-gateway.service` runs as a persistent user service and owns cron.
- `hermes-dashboard.service` is loopback-only by default.  After configuring
  a dashboard authentication provider, an explicit systemd drop-in may set
  `HERMES_DASHBOARD_BIND=tailnet`; the wrapper then waits for the current
  Tailscale IPv4 rather than baking in a stale address at install time.
- Do not maintain duplicate Hermes units under the OneDrive module. The Hermes
  module generates the four specialist gateway units and is their source of
  truth.

## Legacy job disposition

| Job | Linux target | State before re-enabling |
| --- | --- | --- |
| `daily-agent-cron-behavior-audit` | No local workdir | Pin provider/model and verify its Discord delivery. |
| `host-state-manager` | A new, explicit Linux repo root | `D:\\code` has no equivalent on this host. Set `HOST_STATE_ROOT`; dry-run against the intended root. |
| `chirac-classifier` / `chirac-pull-request-queue` | Clone the Chirac repo first | Script and job still hard-code Windows paths. |
| Brassens PR/Sentry/Electron jobs | Clone the Brassens monorepo first | These may create branches, commits, PRs, or merge PRs. Port paths and perform a manual detector run before scheduling. |
| `maria-pull-request-queue` | Clone the Maria repo first | Script and job still hard-code Windows paths. |
| `competitor-analysis` | `~/.hermes/competitor-analysis` | Workspace exists. Port its script default from AppData, run a non-network dry run, then validate the Discord destination. |
| Tuva issue jobs | `~/.hermes/scripts` | Scripts exist but their prompts and workdirs reference Windows. Port script paths and verify each GitHub/Discord flow manually. |
| `artificial-analysis-stt-monitor` | Determine the Linux data source | Its state location remains Windows-only. Do not enable until the source is defined. |

## Specialist-profile cutover

The live jobs must have exactly one owner.  The owner assignment is maintained
in `profile-cron-split.yaml` and follows the standing responsibility of each
profile:

- `correzianlabs-manager`: cross-job operations audit and host-state reports.
- `repository-orchestrator`: repository classifiers, PR queues, Sentry and
  Electron repair flows.
- `marketing`: competitor intelligence and pricing/positioning analysis.
- `life`: Tuva's personal-assistant issue loop and the related STT event
  monitor.

This is a staged migration, not a duplicated rollout.  Until each specialist
profile has a distinct Discord bot token, all target jobs remain disabled and
the default-profile owner continues to be the only active job.  On token
arrival, for each job: install the target profile token, start its gateway,
copy the current job definition to the target profile, verify a manual run and
Discord attribution, then pause the default job before enabling the target.
Never have both definitions enabled.

Each target profile is already a callable Hermes Bot: its identity and
behavior are held in that profile's `profile.yaml` and `SOUL.md`, and its
credential boundary is its own `.env`.  The migration manifest records the
non-secret environment contract, display name, role, model and CLI handle.
Do not commit `.env` files or bot tokens to this repository.  A supplied token
is installed only in its intended profile's `.env`; all profiles may keep the
same Discord delivery channels while presenting different bot identities.

## Re-enable contract

For each job, use this order: update the script and job workdir; pin the
provider/model; run the detector manually with a no-action fixture or dry-run;
verify its delivery channel; enable the schedule; then observe one execution
in `hermes cron runs` before moving on.  Never restore the four copied profile
fleets as independent active copies; choose one owning profile per job.
