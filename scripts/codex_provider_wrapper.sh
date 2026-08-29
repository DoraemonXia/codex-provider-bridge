#!/usr/bin/env bash
set -euo pipefail

codex_cli_bin="$(find "${CODEX_BIN_ROOT:-$HOME/.vscode-server/extensions}" \
  -type f -path '*/bin/linux-x86_64/codex' -perm -111 \
  -print 2>/dev/null | sort -V | tail -n 1)"
if [[ -z "$codex_cli_bin" || ! -x "$codex_cli_bin" ]]; then
  echo "Codex CLI bundled with the VS Code extension was not found." >&2
  exit 127
fi

codex_home="${CODEX_HOME:-$HOME/.codex}"
bridge_config="$codex_home/provider-bridge.env"
read_bridge_value() {
  local key="$1"
  [[ -f "$bridge_config" ]] || return 0
  awk -F= -v key="$key" '$1 == key { value=$0; sub(/^[^=]*=/, "", value); gsub(/^"|"$/, "", value); print value; exit }' "$bridge_config"
}

read_profile_value() {
  local key="$1" profile_file="$2"
  [[ -f "$profile_file" ]] || return 0
  awk -v key="$key" '
    BEGIN { in_root = 1 }
    /^[[:space:]]*\[/ { in_root = 0; next }
    in_root && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      value = $0
      sub(/^[^=]*=/, "", value)
      sub(/[[:space:]]+#.*/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      sub(/^"/, "", value)
      sub(/"$/, "", value)
      print value
      exit
    }
  ' "$profile_file"
}

bridge_alias="${CODEX_BRIDGE_ALIAS:-$(read_bridge_value BRIDGE_ALIAS)}"
provider_name="${CODEX_BRIDGE_PROVIDER:-$(read_bridge_value BRIDGE_PROVIDER)}"
profile_name="${CODEX_BRIDGE_PROFILE:-$(read_bridge_value BRIDGE_PROFILE)}"
bridge_alias="${bridge_alias:-alt}"
provider_name="${provider_name:-$bridge_alias}"
profile_name="${profile_name:-$bridge_alias}"
[[ "$bridge_alias" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid bridge alias." >&2; exit 2; }
[[ "$provider_name" =~ ^[A-Za-z0-9._:/-]+$ ]] || { echo "Invalid bridge provider ID." >&2; exit 2; }
[[ "$profile_name" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid bridge profile name." >&2; exit 2; }

# A single `codex` executable is shared by all configured providers. Profiles
# are the registry: setup_provider.sh writes <alias>.config.toml, and a
# matching first argument selects that profile. Keep the env-file fallback for
# installations made by older versions of this skill.
profile_route=0
requested_alias="${1:-}"
if [[ "$requested_alias" =~ ^[A-Za-z0-9_-]+$ ]]; then
  requested_profile="$codex_home/$requested_alias.config.toml"
  requested_provider="$(read_profile_value model_provider "$requested_profile")"
  if [[ -n "$requested_provider" && "$requested_provider" =~ ^[A-Za-z0-9._:/-]+$ ]]; then
    bridge_alias="$requested_alias"
    provider_name="$requested_provider"
    profile_name="$requested_alias"
    profile_route=1
  elif [[ "$requested_alias" == "$bridge_alias" ]]; then
    # Compatibility with a pre-multi-profile installation whose provider
    # definition is only described by provider-bridge.env.
    profile_route=1
  fi
fi

restore_dir="$codex_home/provider-bridge-restore"
start_epoch="$(date +%s)"
declare -A existing_alt_threads=()

find_state_db() {
  local candidate state_db=""
  for candidate in "$codex_home"/state_*.sqlite; do
    [[ -f "$candidate" ]] || continue
    state_db="$candidate"
  done
  if [[ -n "$state_db" ]]; then
    printf '%s\n' "$state_db"
  fi
  return 0
}

read_base_config_value() {
  local key="$1" config_file="$codex_home/config.toml"
  [[ -f "$config_file" ]] || return 0
  awk -v key="$key" '
    BEGIN { in_root = 1 }
    /^[[:space:]]*\[/ { in_root = 0; next }
    in_root && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      value = $0
      sub(/^[^=]*=/, "", value)
      sub(/[[:space:]]+#.*/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      sub(/^"/, "", value)
      sub(/"$/, "", value)
      print value
      exit
    }
  ' "$config_file"
}

lock_is_live() {
  local lock_file="$1"
  [[ -e "$lock_file" ]] || return 1
  if command -v fuser >/dev/null 2>&1; then
    fuser -s "$lock_file" 2>/dev/null
    return $?
  fi
  return 0
}

ensure_thread_available() {
  local thread_id="$1" lock_file="$codex_home/thread-writer-locks/$1.lock"
  if lock_is_live "$lock_file"; then
    echo "会话 $thread_id 仍被其他 Codex 进程使用；请关闭聊天并执行 Developer: Restart Extension Host。" >&2
    return 1
  fi
}

list_threads() {
  local state_db
  state_db="$(find_state_db)"
  [[ -n "$state_db" ]] || return 0
  sqlite3 -readonly -noheader -separator $'\t' "$state_db" '
    SELECT id,
      substr(replace(replace(replace(
        coalesce(nullif(title, ""), nullif(first_user_message, ""), "(untitled)"),
        char(9), " "), char(10), " "), char(13), " "), 1, 100)
    FROM threads
    WHERE archived = 0 AND thread_source = "user"
    ORDER BY recency_at DESC, updated_at DESC;
  ' 2>/dev/null
}

choose_thread() {
  local row session_id session_title state_db
  state_db="$(find_state_db)"
  [[ -n "$state_db" ]] || return 1
  command -v sqlite3 >/dev/null 2>&1 || return 1
  mapfile -t session_rows < <(list_threads)
  [[ "${#session_rows[@]}" -gt 0 ]] || return 1
  choices=()
  session_ids=()
  for row in "${session_rows[@]}"; do
    IFS=$'\t' read -r session_id session_title <<< "$row"
    session_ids+=("$session_id")
    choices+=("${session_id:0:8}  $session_title")
  done
  PS3="选择要使用替代 Provider 的会话（输入编号，Ctrl-C 退出）： "
  select choice in "${choices[@]}"; do
    if [[ -n "${choice:-}" ]]; then
      selected_id="${session_ids[$((REPLY - 1))]}"
      return 0
    fi
    echo "请输入有效编号。" >&2
  done
}

save_thread_restore_state() {
  local thread_id="$1" state_db restore_file temp_file
  local original_provider original_model original_effort
  [[ "$thread_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || return 0
  state_db="$(find_state_db)"
  [[ -n "$state_db" ]] || return 0
  mkdir -p -- "$restore_dir"
  chmod 700 -- "$restore_dir"
  restore_file="$restore_dir/$thread_id"
  [[ -e "$restore_file" ]] && return 0

  IFS=$'\t' read -r original_provider original_model original_effort < <(
    sqlite3 -readonly -separator $'\t' "$state_db" \
      "SELECT coalesce(nullif(model_provider, ''), 'openai'), coalesce(model, ''), coalesce(reasoning_effort, '')
       FROM threads WHERE id = '$thread_id';" 2>/dev/null
  ) || true
  [[ -n "${original_provider:-}" && "$original_provider" != "$provider_name" ]] || return 0
  original_model="${original_model:-$(read_base_config_value model)}"
  original_effort="${original_effort:-$(read_base_config_value model_reasoning_effort)}"
  [[ -n "$original_model" ]] || return 0
  [[ "$original_provider" =~ ^[A-Za-z0-9._:/-]+$ && "$original_model" =~ ^[A-Za-z0-9._:/-]+$ ]] || return 0
  [[ -z "$original_effort" || "$original_effort" =~ ^[A-Za-z0-9._:-]+$ ]] || return 0

  temp_file="$(mktemp "$restore_dir/.${thread_id}.XXXXXX")"
  chmod 600 -- "$temp_file"
  printf '%s\t%s\t%s\n' "$original_provider" "$original_model" "$original_effort" > "$temp_file"
  mv -- "$temp_file" "$restore_file"
}

restore_thread_state() {
  local thread_id="$1" state_db lock_file restore_file current_provider change_count
  local restore_provider restore_model restore_effort restore_effort_sql
  [[ "$thread_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || return 0
  state_db="$(find_state_db)"
  if [[ -z "$state_db" ]] || ! command -v sqlite3 >/dev/null 2>&1; then
    echo "无法恢复会话 $thread_id：找不到 Codex state DB 或 sqlite3。" >&2
    return 1
  fi
  lock_file="$codex_home/thread-writer-locks/$thread_id.lock"
  if lock_is_live "$lock_file"; then
    echo "会话 $thread_id 仍被其他 Codex 进程使用，保留恢复快照。" >&2
    return 1
  fi

  restore_file="$restore_dir/$thread_id"
  if [[ -f "$restore_file" ]]; then
    IFS=$'\t' read -r restore_provider restore_model restore_effort < "$restore_file"
  else
    restore_provider="$(read_base_config_value model_provider)"
    restore_model="$(read_base_config_value model)"
    restore_effort="$(read_base_config_value model_reasoning_effort)"
  fi
  restore_provider="${restore_provider:-openai}"
  [[ -n "$restore_model" ]] || { echo "会话 $thread_id 未恢复：基础 config 没有默认 model。" >&2; return 1; }
  [[ "$restore_provider" =~ ^[A-Za-z0-9._:/-]+$ && "$restore_model" =~ ^[A-Za-z0-9._:/-]+$ ]] || return 1
  [[ -z "$restore_effort" || "$restore_effort" =~ ^[A-Za-z0-9._:-]+$ ]] || return 1
  restore_effort_sql="NULL"
  [[ -n "$restore_effort" ]] && restore_effort_sql="'$restore_effort'"

  if ! change_count="$(sqlite3 -cmd '.timeout 5000' "$state_db" <<SQL
BEGIN IMMEDIATE;
UPDATE threads
SET model_provider = '$restore_provider', model = '$restore_model', reasoning_effort = $restore_effort_sql
WHERE id = '$thread_id' AND model_provider = '$provider_name' AND archived = 0;
SELECT changes();
COMMIT;
SQL
)"; then
    echo "会话 $thread_id 恢复失败，保留 $provider_name 状态和快照。" >&2
    return 1
  fi
  change_count="$(printf '%s\n' "$change_count" | tail -n 1)"
  if [[ "$change_count" == "1" ]]; then
    rm -- "$restore_file" 2>/dev/null || true
    echo "会话 $thread_id 已恢复为 $restore_provider / $restore_model / ${restore_effort:-default}。" >&2
  else
    current_provider="$(sqlite3 -readonly -noheader "$state_db" \
      "SELECT coalesce(model_provider, '') FROM threads WHERE id = '$thread_id';" 2>/dev/null || true)"
    [[ "$current_provider" != "$provider_name" ]] && rm -- "$restore_file" 2>/dev/null || true
  fi
}

restore_new_threads() {
  local state_db thread_id
  state_db="$(find_state_db)"
  [[ -n "$state_db" ]] || return 0
  while IFS= read -r thread_id; do
    [[ -n "$thread_id" && -z "${existing_alt_threads[$thread_id]:-}" ]] || continue
    restore_thread_state "$thread_id" || true
  done < <(sqlite3 -readonly -noheader "$state_db" \
    "SELECT id FROM threads WHERE model_provider = '$provider_name'
     AND archived = 0 AND thread_source = 'user' AND created_at >= $start_epoch;" 2>/dev/null)
}

run_alternate_and_restore() {
  local restore_id="$1" status=0
  shift
  if [[ -n "$restore_id" ]]; then
    ensure_thread_available "$restore_id" || return 1
    save_thread_restore_state "$restore_id" || true
  fi
  "$codex_cli_bin" --profile "$profile_name" "$@" || status=$?
  if [[ -n "$restore_id" ]]; then
    restore_thread_state "$restore_id" || true
  else
    restore_new_threads
  fi
  return "$status"
}

if (( profile_route )); then
  shift
  state_db="$(find_state_db)"
  if [[ -n "$state_db" ]] && command -v sqlite3 >/dev/null 2>&1; then
    while IFS= read -r existing_thread_id; do
      [[ -n "$existing_thread_id" ]] && existing_alt_threads["$existing_thread_id"]=1
    done < <(sqlite3 -readonly -noheader "$state_db" \
      "SELECT id FROM threads WHERE model_provider = '$provider_name' AND archived = 0 AND thread_source = 'user';" 2>/dev/null)
  fi

  if [[ "${1:-}" == "resume" ]]; then
    shift
    picker_request=1
    for argument in "$@"; do
      case "$argument" in
        --all|--include-non-interactive) ;;
        *) picker_request=0 ;;
      esac
    done
    if (( picker_request )); then
      if choose_thread; then
        run_alternate_and_restore "$selected_id" resume "$@"
        exit $?
      fi
      echo "无法读取本地会话索引，回退到 Codex 自带恢复列表。" >&2
      exec "$codex_cli_bin" --profile "$profile_name" resume --all --include-non-interactive
    fi

    restore_id=""
    for argument in "$@"; do
      if [[ "$argument" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        restore_id="$argument"
        break
      fi
    done
    run_alternate_and_restore "$restore_id" resume "$@"
    exit $?
  fi

  run_alternate_and_restore "" "$@"
  exit $?
fi

exec "$codex_cli_bin" "$@"
