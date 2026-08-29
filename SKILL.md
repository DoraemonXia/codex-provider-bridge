---
name: codex-provider-bridge
description: Configure a user-supplied OpenAI-compatible API as a temporary Codex CLI profile while preserving the normal VS Code/OpenAI profile and shared local sessions; diagnose provider visibility, timeouts, writer locks, and restore failures.
---

# Codex Provider Bridge

Use this skill when a user wants to run Codex from a terminal through another OpenAI-compatible endpoint, keep the normal VS Code Codex login intact, and make the change reversible after the CLI exits.

The intended design is local and provider-agnostic:

1. Keep the user's base `config.toml` default provider/model unchanged.
2. Put the alternate endpoint in a profile file under `$CODEX_HOME` and keep its key in a mode-600 file, never in this repository.
3. Install a small `codex` wrapper that forwards ordinary commands to the bundled CLI and maps a configurable alias such as `codex alt` to its matching profile.
4. For a shared session, select a UUID from the local state database, refuse to start when another Codex writer owns its lock, snapshot its current provider/model/reasoning settings, and restore those values after the child exits.
5. Add the provider definition to the base config so the VS Code app-server can open a thread that was temporarily written by the alternate provider. Do not patch the VS Code extension.

Read the relevant reference before acting:

- New setup or a changed URL/key: [references/setup.md](references/setup.md)
- Normal operation and shutdown: [references/operations.md](references/operations.md)
- A failure, timeout, missing thread, or lock: [references/troubleshooting.md](references/troubleshooting.md)
- A newly verified pitfall or fix: [references/maintenance.md](references/maintenance.md)

Run `scripts/setup_provider.sh` for installation and `scripts/doctor_provider.sh` for read-only diagnostics. Both scripts must avoid printing secrets. Validate scripts after edits and do not commit local config, SQLite databases, rollout logs, key files, restore snapshots, or VS Code extension files.

Important limitations:

- This shares the local Codex thread/index and rollout history; it does not make a third-party Responses API understand OpenAI's `previous_response_id` state. Do not promise identical backend continuation semantics.
- The provider field is not currently exposed by the app-server settings update API. The wrapper's post-exit SQLite update is therefore a narrow compatibility workaround, guarded by an exact UUID, provider check, transaction, lock check, and failure-preserving behavior.
- A hard kill, power loss, process crash before cleanup, a database schema change, or a concurrent writer can prevent automatic restoration. Preserve the snapshot and diagnose; never run a broad `pkill codex`.
- Public documentation and incident reports may contain endpoint/model/version information, but never API keys, auth files, rollout contents, personal prompts, or raw logs.
