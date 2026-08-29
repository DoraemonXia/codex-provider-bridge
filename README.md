# Codex Provider Bridge

A reusable Codex skill and wrapper for temporarily using a user-provided OpenAI-compatible endpoint from a terminal:

```text
codex alt
codex alt resume
codex alt resume <thread-uuid>
```

The normal `codex` command remains on the user's existing provider. The wrapper shares Codex's local thread index with VS Code, but restores the selected thread's original provider/model/reasoning settings after the alternate process exits. The alias, provider ID, profile filename, endpoint, and model are configurable. It does not modify the VS Code extension.

## Install

Read [the setup reference](references/setup.md). The normal setup is interactive so the key is not placed in shell history:

```bash
git clone https://github.com/DoraemonXia/codex-provider-bridge.git
cd codex-provider-bridge
scripts/setup_provider.sh --alias alt --base-url https://example.invalid/v1 --model gpt-5.6-terra
```

The script asks for the API key, stores it in a mode-600 file, creates the selected profile under `$CODEX_HOME`, preserves the base default provider, and installs the wrapper to `~/.local/bin/codex` unless another path is supplied. Ensure that directory is in `PATH` before the bundled extension binary.

## Safe operation

Before reusing a VS Code conversation from the terminal:

1. Close the active Codex chat/window for that conversation.
2. In VS Code run `Developer: Reload Window` (or `Developer: Restart Extension Host` when available).
3. Confirm the target lock is no longer held with `fuser -v "$CODEX_HOME/thread-writer-locks/<uuid>.lock"`.
4. Run `codex alt resume` and select the conversation (replace `alt` with the configured alias).
5. When finished, exit the terminal Codex normally. The wrapper restores the saved provider state.

Do not manually remove an actively held lock, kill all Codex processes, or commit a key/config/database. For incidents, follow [references/maintenance.md](references/maintenance.md) and contribute a redacted branch or pull request.
