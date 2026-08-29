# Troubleshooting

## `thread already has an active writer`

Cause: the VS Code app-server or another CLI still owns the exact thread lock.

```bash
fuser -v "$CODEX_HOME/thread-writer-locks/<uuid>.lock"
```

If a PID is shown, close that Codex chat and run `Developer: Restart Extension Host` (`workbench.action.restartExtensionHost`). Use `Developer: Reload Window` only as a fallback. Do not delete the lock or kill unrelated Codex processes. If no PID is shown, retry the exact command; a stale lock file is not proof of an active writer.

## The alternate-provider conversation is missing from the picker

The built-in picker commonly filters by the active provider. Use `codex <alias> resume` so the wrapper selects from the shared local index, or pass the complete UUID. `--all` alone does not defeat provider filtering in every CLI version; the wrapper treats a picker-style `resume --all` as a shared-index selection when possible.

If VS Code cannot open a thread after it is restored, verify that the base config contains the same provider definition. The provider definition must exist even when the default provider remains OpenAI.

## The model still shows Luna

Check which command is being executed:

```bash
command -v codex
type -a codex
codex <alias> --help
```

The wrapper must precede the extension's bundled binary in `PATH`, and the selected profile must set both `model = "..."` and its `model_provider`. A new session may show the base model if the wrapper was bypassed.

## Timeout or `reconnecting`

Check the endpoint path, network reachability, API compatibility, and idle timeout. The provider must support the wire protocol configured in the profile (`responses` in the supplied implementation). Use modest retry counts and a bounded stream idle timeout. Do not “fix” a network timeout by changing the VS Code extension or by running two Codex writers concurrently.

## The plugin cannot resume an alternate-provider thread

First check the current index row with the doctor. If it still says the alternate provider, the exit cleanup did not run or was blocked by a live lock. Keep the restore snapshot, close/reload the owner, and rerun the doctor before any repair. Never rewrite rollout history or delete the SQLite database.

## Automatic restore did not happen

Expected causes are a hard kill/power loss, a process crash, a still-live lock, a changed SQLite schema, or a missing base default model. Inspect `$CODEX_HOME/provider-bridge-restore/<uuid>` and the exact thread row. Repair only the exact UUID after confirming no live lock; preserve the snapshot until the repair is verified. If the database layout changed in a new Codex release, update the skill and add a regression note before changing the SQL.
