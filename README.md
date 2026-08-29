# Codex Provider Bridge

A reusable Codex skill and wrapper for temporarily using a user-provided OpenAI-compatible endpoint from a terminal:

```text
codex alt
codex alt resume
codex alt resume <thread-uuid>
```

The normal `codex` command remains on the user's existing provider. The wrapper shares Codex's local thread index with VS Code, but restores the selected thread's original provider/model/reasoning settings after the alternate process exits. The alias, provider ID, profile filename, endpoint, and model are configurable. It does not modify the VS Code extension.

One installed `codex` entry point can serve multiple alternate providers. Each
provider gets its own `$CODEX_HOME/<alias>.config.toml`, and the wrapper routes
`codex <alias>` to the matching profile. Running the installer again with a
different alias adds another provider instead of making the newest provider the
only recognized alias.

## Install

Read [the setup reference](references/setup.md). The normal setup is interactive so the key is not placed in shell history:

```bash
git clone https://github.com/DoraemonXia/codex-provider-bridge.git
cd codex-provider-bridge
scripts/setup_provider.sh --alias alt --base-url https://example.invalid/v1 --model gpt-5.6-terra
```

The script asks for the API key, stores it in a mode-600 file, creates the selected profile under `$CODEX_HOME`, preserves the base default provider, and installs the shared wrapper to `~/.local/bin/codex` unless another path is supplied. Ensure that directory is in `PATH` before the bundled extension binary.

To add another provider later, run the installer again with a different alias:

```bash
scripts/setup_provider.sh --alias other --base-url https://example.invalid/v1 --model other-model
```

Existing profiles remain available, for example `codex alt` and `codex other`.

## Safe operation

Before reusing a VS Code conversation from the terminal:

1. Close the active Codex chat/window for that conversation.
2. In VS Code run `Developer: Restart Extension Host` (`workbench.action.restartExtensionHost`). Use `Developer: Reload Window` only if the extension-host command is unavailable or does not release the process.
3. Confirm the target lock is no longer held with `fuser -v "$CODEX_HOME/thread-writer-locks/<uuid>.lock"`.
4. Run `codex <alias> resume` and select the conversation (replace `<alias>` with the configured provider alias).
5. When finished, exit the terminal Codex normally. The wrapper restores the saved provider state.

Do not manually remove an actively held lock, kill all Codex processes, or commit a key/config/database. For incidents, follow [references/maintenance.md](references/maintenance.md) and contribute a redacted branch or pull request.
