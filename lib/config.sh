#!/bin/bash
# SCI Config — pure shell, no external dependencies
# Format: sourceable key=value file + plain text list files

SCI_CONFIG_DIR="$HOME/.sci"
SCI_CONFIG_FILE="$SCI_CONFIG_DIR/sci-config.sh"
SCI_PROJECTS_FILE="$SCI_CONFIG_DIR/projects.list"
SCI_BLOCKED_FILE="$SCI_CONFIG_DIR/blocked-paths.list"

# --- State variables (populated by config_load or setup prompts) ---
SCI_USER_NAME=""
SCI_USER_UID=""
SCI_GROUP_NAME=""
SCI_GROUP_GID=""
SCI_MAIN_USER=""
SCI_MAIN_HOME=""
SCI_PROJECTS_DIR=""
SCI_PERM_MODE=""
SCI_ACL=""
SCI_CREATED=""
SCI_UPDATED=""
SCI_PROMPT_FILE=""

# --- Arrays loaded from list files ---
SCI_PROJECTS=()
SCI_BLOCKED_PATHS=()

config_exists() {
  [ -f "$SCI_CONFIG_FILE" ]
}

config_load() {
  if ! config_exists; then
    return 1
  fi

  # Source the key=value file — sets all SCI_* variables
  source "$SCI_CONFIG_FILE"

  # Load projects list
  SCI_PROJECTS=()
  if [ -f "$SCI_PROJECTS_FILE" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && SCI_PROJECTS+=("$line")
    done < "$SCI_PROJECTS_FILE"
  fi

  # Load blocked paths list
  SCI_BLOCKED_PATHS=()
  if [ -f "$SCI_BLOCKED_FILE" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && SCI_BLOCKED_PATHS+=("$line")
    done < "$SCI_BLOCKED_FILE"
  fi

  return 0
}

config_write() {
  mkdir -p "$SCI_CONFIG_DIR"

  cat > "$SCI_CONFIG_FILE" << EOF
# SCI Config — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Do not edit manually unless you know what you're doing.

SCI_USER_NAME="$SCI_USER_NAME"
SCI_USER_UID="$SCI_USER_UID"
SCI_GROUP_NAME="$SCI_GROUP_NAME"
SCI_GROUP_GID="$SCI_GROUP_GID"
SCI_MAIN_USER="$SCI_MAIN_USER"
SCI_MAIN_HOME="/Users/$SCI_MAIN_USER"
SCI_PROJECTS_DIR="$SCI_PROJECTS_DIR"
SCI_PERM_MODE="shared_ownership"
SCI_ACL="list,search,read,write,execute,add_file,add_subdirectory,delete,delete_child,readattr,writeattr,readextattr,writeextattr,file_inherit,directory_inherit"
SCI_CREATED="${SCI_CREATED:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
SCI_UPDATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SCI_PROMPT_FILE="$SCI_PROMPT_FILE"
EOF
  chmod 600 "$SCI_CONFIG_FILE"

  # Write list files
  printf '%s\n' "${SCI_PROJECTS[@]}" > "$SCI_PROJECTS_FILE" 2>/dev/null || true
  printf '%s\n' "${SCI_BLOCKED_PATHS[@]}" > "$SCI_BLOCKED_FILE" 2>/dev/null || true
}

config_touch() {
  if config_exists; then
    sed -i '' "s/^SCI_UPDATED=.*/SCI_UPDATED=\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"/" "$SCI_CONFIG_FILE"
  fi
}

config_add_project() {
  local path="$1"
  # Avoid duplicates
  if [ -f "$SCI_PROJECTS_FILE" ] && grep -qxF "$path" "$SCI_PROJECTS_FILE"; then
    return 0
  fi
  echo "$path" >> "$SCI_PROJECTS_FILE"
  config_touch
}

config_remove_project() {
  local path="$1"
  if [ -f "$SCI_PROJECTS_FILE" ]; then
    local tmp=$(mktemp)
    grep -vxF "$path" "$SCI_PROJECTS_FILE" > "$tmp" || true
    mv "$tmp" "$SCI_PROJECTS_FILE"
    config_touch
  fi
}

# Find first available UID >= 500 not in use
find_available_uid() {
  local uid=500
  local used
  used=$(dscl . -list /Users UniqueID 2>/dev/null | awk '{print $2}' | sort -n)
  while echo "$used" | grep -q "^${uid}$"; do
    uid=$((uid + 1))
  done
  echo "$uid"
}

# Find first available GID >= 500 not in use
find_available_gid() {
  local gid=500
  local used
  used=$(dscl . -list /Groups PrimaryGroupID 2>/dev/null | awk '{print $2}' | sort -n)
  while echo "$used" | grep -q "^${gid}$"; do
    gid=$((gid + 1))
  done
  echo "$gid"
}

# Check if a macOS user exists in dscl
user_exists() {
  dscl . -read "/Users/$1" &>/dev/null
}

# Check if a macOS group exists in dscl
group_exists() {
  dscl . -read "/Groups/$1" &>/dev/null
}
