# Operation and shutdown

## Why the wrapper is needed

Codex's profile overlay changes the CLI's active provider, while the VS Code app-server filters its thread list by the default provider. Therefore the built-in alternate-provider resume picker may hide normal OpenAI threads. The wrapper reads the shared local `state_*.sqlite`, lets the user choose a UUID, and passes that exact UUID to the selected profile.

The wrapper does not rewrite rollout history. It changes only the current thread index row after the child exits, and only when that row is still the selected alternate provider. The first session metadata and historical turns remain evidence of which provider handled each turn.

## Recommended sequence

1. Finish or close the normal Codex chat that owns the target thread.
2. Run VS Code `Developer: Reload Window`; this restarts the extension host/app-server without deleting conversations.
3. Check a target lock with `fuser -v "$CODEX_HOME/thread-writer-locks/<uuid>.lock"`.
4. Run `codex <alias> resume` and choose the thread, or pass the complete UUID.
5. Use the alternate provider.
6. Exit the CLI normally, including Ctrl-C from the TUI. The wrapper preserves the child exit status and then attempts restoration.
7. Use ordinary `codex`/VS Code again only after the alternate process has exited and the lock is no longer held.

## New sessions

When `codex <alias>` starts a new session, there may be no UUID to snapshot before the first message. After exit, the wrapper identifies new user threads created during that invocation and restores them from the base config. Set a real default `model` in the base config if fallback restoration is required; otherwise the wrapper keeps the alternate row and reports why it could not infer a default.

## Concurrency rule

Never open the same thread in the VS Code Codex app-server and the terminal CLI at the same time. A writer lock is per thread, not a global service switch. The bridge refuses a known live lock and never kills the owning process. If VS Code still owns it, close the chat and reload the window/extension host. Do not use `pkill`, `killall`, or a broad `kill` command.
