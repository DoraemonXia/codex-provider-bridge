# Setup and configuration

## Inputs

Ask for:

- the alternate endpoint URL, including the API version path required by that service;
- the model name, for example `gpt-5.6-terra`;
- optional reasoning effort, defaulting to `high` only when the provider supports it;
- the user's Codex home if it is not `$HOME/.codex`.

Do not ask the user to put the API key in a command-line argument. Prefer an interactive hidden prompt or an existing key file. A key file must be mode 600 and must not be inside the Git repository.

## Automated installation

From the cloned skill directory:

```bash
scripts/setup_provider.sh \
  --alias alt \
  --base-url 'https://provider.example/v1' \
  --model 'gpt-5.6-terra' \
  --reasoning-effort high
```

For a secret manager or pre-created file:

```bash
scripts/setup_provider.sh \
  --alias alt \
  --base-url 'https://provider.example/v1' \
  --api-key-file '/secure/path/provider.key' \
  --model 'gpt-5.6-terra'
```

The installer:

- creates `$CODEX_HOME/<alias>.config.toml` with the selected `model_provider`;
- reads authentication through `/usr/bin/cat <key-file>` so the key is not embedded in TOML or process arguments;
- adds the same provider definition to the base config only if it is missing, leaving the base default provider/model unchanged;
- installs the dynamic wrapper, which discovers the newest executable bundled by the VS Code extension;
- backs up an existing wrapper before replacing it;
- does not edit the VS Code extension, kill processes, or add credentials to Git.

If the selected provider table already exists, inspect its URL, wire protocol, and auth path rather than blindly appending a duplicate TOML table. A duplicate table can make Codex fail before it starts.

## Expected files

```text
$CODEX_HOME/config.toml          # normal/default provider; keep it stable
$CODEX_HOME/<alias>.config.toml  # alternate profile, no secret value
$CODEX_HOME/<alias>-api-key      # mode 600, local-only secret
$CODEX_HOME/provider-bridge-restore/<uuid> # short-lived restoration snapshot
~/.local/bin/codex                # wrapper, before the extension binary in PATH
```

The command alias, provider ID, profile filename, endpoint, model, and reasoning effort are independent settings. Avoid reusing a provider ID that belongs to another service.

## Verification

Run:

```bash
scripts/doctor_provider.sh
codex --version
codex alt --help
```

Then perform a low-cost test with a disposable or already-restored conversation. Verify the visible model is the alternate model, send one harmless message only if the user consents, exit normally, and run the doctor again. A no-message launch may not change the thread's provider row; that is expected and should not be treated as a failed restore.
