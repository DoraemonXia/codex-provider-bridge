#!/usr/bin/env bash
set -euo pipefail

codex_home="${CODEX_HOME:-$HOME/.codex}"
thread_id=""
if [[ "${1:-}" == "--thread-id" && $# -ge 2 ]]; then
  thread_id="$2"
fi

echo "CODEX_HOME=$codex_home"
wrapper="$HOME/.local/bin/codex"
if [[ -x "$wrapper" ]]; then echo "wrapper=present:$wrapper"; else echo "wrapper=missing:$wrapper"; fi
if [[ -f "$codex_home/provider-bridge.env" ]]; then echo "bridge_config=present"; else echo "bridge_config=missing"; fi
if [[ -f "$codex_home/config.toml" ]]; then
  echo "base_config=present"
  if command -v rg >/dev/null 2>&1; then
    rg -q '^\[model_providers\.' "$codex_home/config.toml" && echo "base_provider=present" || echo "base_provider=missing"
  else
    grep -Eq '^\[model_providers\.' "$codex_home/config.toml" && echo "base_provider=present" || echo "base_provider=missing"
  fi
else
  echo "base_config=missing"
  echo "base_provider=missing"
fi
if [[ -f "$codex_home/provider-bridge-restore" ]]; then echo "restore_path=unexpected_file"; elif [[ -d "$codex_home/provider-bridge-restore" ]]; then echo "restore_dir=present"; else echo "restore_dir=missing"; fi
if command -v sqlite3 >/dev/null 2>&1; then echo "sqlite3=present"; else echo "sqlite3=missing"; fi

bridge_provider=""
if [[ -f "$codex_home/provider-bridge.env" ]]; then
  bridge_provider="$(awk -F= '$1 == "BRIDGE_PROVIDER" { value=$0; sub(/^[^=]*=/, "", value); gsub(/^"|"$/, "", value); print value; exit }' "$codex_home/provider-bridge.env")"
  echo "provider_id=${bridge_provider:-unknown}"
fi

profile_count=0
for profile_file in "$codex_home"/*.config.toml; do
  [[ -f "$profile_file" ]] || continue
  profile_name="$(basename -- "$profile_file" .config.toml)"
  profile_provider="$(awk '
    BEGIN { in_root = 1 }
    /^[[:space:]]*\[/ { in_root = 0; next }
    in_root && /^[[:space:]]*model_provider[[:space:]]*=/ {
      value = $0
      sub(/^[^=]*=/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      sub(/^"/, "", value)
      sub(/"$/, "", value)
      print value
      exit
    }
  ' "$profile_file")"
  if [[ "$profile_name" =~ ^[A-Za-z0-9_-]+$ && "$profile_provider" =~ ^[A-Za-z0-9._:/-]+$ ]]; then
    echo "profile=${profile_name}:${profile_provider}"
    profile_count=$((profile_count + 1))
  fi
done
echo "profiles=${profile_count}"

state_db=""
for candidate in "$codex_home"/state_*.sqlite; do
  [[ -f "$candidate" ]] && state_db="$candidate"
done
if [[ -n "$state_db" ]]; then
  echo "state_db=$state_db"
  if [[ -n "$thread_id" ]]; then
    if [[ "$thread_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
      sqlite3 -readonly -header -column "$state_db" \
        "SELECT id, model_provider, model, reasoning_effort, archived, thread_source, substr(title,1,80) AS title FROM threads WHERE id = '$thread_id';" 2>/dev/null || echo "thread_query=failed"
      lock_file="$codex_home/thread-writer-locks/$thread_id.lock"
      if [[ -e "$lock_file" ]]; then
        if command -v fuser >/dev/null 2>&1 && fuser -v "$lock_file" 2>&1; then :; else echo "lock_file=present_no_live_owner_reported"; fi
      else
        echo "lock_file=absent"
      fi
    else
      echo "thread_query=invalid_uuid" >&2
    fi
  fi
else
  echo "state_db=missing"
fi

echo "No secrets or rollout contents are printed by this diagnostic."
