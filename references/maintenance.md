# Maintenance and community updates

## What counts as a useful incident

Record only reproducible, decision-changing facts:

- date and Codex/extension version;
- operating system and whether VS Code app-server was running;
- redacted command and symptom;
- exact cause after inspection;
- verified fix and regression check;
- whether the fix depends on a specific SQLite schema or provider behavior.

Do not record API keys, auth files, prompts, rollout contents, raw logs, account identifiers, private URLs, or full database dumps.

## Updating the skill

When a new pitfall is verified, update the smallest relevant reference and add a short dated entry to the repository history or an incident section. Keep the wrapper defensive and provider-agnostic; do not turn one machine's absolute path or one model name into a universal constant. Run:

```bash
python3 /path/to/skill-creator/scripts/quick_validate.py .
bash -n scripts/*.sh
```

For a proposed change, create a branch such as `experience/2026-08-29-stale-lock`, test it against a disposable local session, and open a pull request. Never push a key or local Codex state.

## Contributions from other users

A public repository cannot accept anonymous direct pushes. Other users should fork the repository and open a redacted pull request, or configure their own GitHub SSH/PAT access before the skill attempts to push a branch. The skill may help prepare the branch and validate it, but it must not upload diagnostics automatically without explicit authorization.

## Compatibility policy

Prefer the official bundled CLI and public app-server behavior. The SQLite provider restoration exists only because the current public settings update method does not change `model_provider`. If a future Codex version exposes an official provider-setting operation, test it independently and replace the direct database update only after verifying thread listing, resume, locks, interruption cleanup, and VS Code compatibility.

## Verified incidents

- 2026-08-29: A missing `state_*.sqlite` made a command-substitution helper return status 1 under `set -e`, so even a help invocation exited silently. The wrapper now treats an absent state database as an empty result and continues to the bundled CLI; regression coverage includes setup in an empty temporary Codex home and an alternate-alias `--help` invocation.
- 2026-08-29: The shutdown instruction was clarified to use VS Code `Developer: Restart Extension Host` first, with `Developer: Reload Window` as fallback. This better targets the extension-host/app-server process and avoids unnecessarily reloading the whole window.
- 2026-08-29: Installing a second provider replaced a pre-existing single-provider wrapper, leaving its profile and key intact but making its `codex <old-alias>` shortcut fall through to the bundled CLI. The wrapper now treats `<alias>.config.toml` files as a multi-provider registry and routes each matching alias through the same guarded restore logic; the installer can therefore be rerun for additional providers without making the newest alias exclusive.
- 2026-08-30: The setup guide incorrectly presented `codex --profile <alias>` as equivalent to the wrapper alias route. That form bypasses the wrapper's thread snapshot and restoration, so the guide now reserves it for direct CLI use and directs shared conversations through `codex <alias> resume`.
