#!/bin/bash
# SCI Setup — full interactive setup for a new machine

SETUP_TOTAL_STEPS=10

run_setup() {
  sci_header

  # Guard: already configured?
  if config_exists; then
    config_load
    echo -e "  ${YELLOW}${ICON_WARN}${NC} SCI is already configured on this machine."
    echo -e "     User: ${BOLD}$SCI_USER_NAME${NC} (UID $SCI_USER_UID)"
    echo -e "     Projects dir: $SCI_PROJECTS_DIR"
    echo ""
    if ! confirm "Overwrite existing config and re-run setup?"; then
      echo "  Aborted."
      return 0
    fi
    echo ""
  fi

  # Guard: must be run as your normal user
  if [ "$(id -u)" -eq 0 ]; then
    error_banner "Don't run as root" "Run as your normal user — SCI will sudo when needed."
    return 1
  fi

  section "Configuration"

  SCI_MAIN_USER="$(whoami)"
  SCI_MAIN_HOME="/Users/$SCI_MAIN_USER"
  echo -e "  ${ICON_ARROW} Main user detected: ${BOLD}$SCI_MAIN_USER${NC} ${GREEN}${ICON_OK}${NC}"

  SCI_USER_NAME=$(prompt_value "Username for isolated user" "claude-dev")
  SCI_GROUP_NAME=$(prompt_value "Group name" "claude")

  local default_projects_dir="$SCI_MAIN_HOME/Documents/claude-projects"
  SCI_PROJECTS_DIR=$(prompt_value "Projects directory" "$default_projects_dir")

  local blocked_input
  blocked_input=$(prompt_value "Folder name to block in projects" "security_data")
  SCI_BLOCKED_PATHS=()
  IFS=',' read -ra SCI_BLOCKED_PATHS <<< "$blocked_input"

  # Prompt file option
  SCI_PROMPT_FILE=""
  if confirm "Create a prompt notepad file? (opens with claude-shell)"; then
    SCI_PROMPT_FILE="$SCI_PROJECTS_DIR/prompt.md"
  fi

  # Auto-detect UID/GID
  if group_exists "$SCI_GROUP_NAME"; then
    SCI_GROUP_GID=$(dscl . -read "/Groups/$SCI_GROUP_NAME" PrimaryGroupID 2>/dev/null | awk '{print $2}')
    echo -e "  ${ICON_ARROW} Group '${SCI_GROUP_NAME}' exists (GID $SCI_GROUP_GID) — will reuse" >&2
  else
    SCI_GROUP_GID=$(find_available_gid)
    echo -e "  ${ICON_ARROW} Group GID auto-selected: ${BOLD}$SCI_GROUP_GID${NC}" >&2
  fi

  if user_exists "$SCI_USER_NAME"; then
    SCI_USER_UID=$(dscl . -read "/Users/$SCI_USER_NAME" UniqueID 2>/dev/null | awk '{print $2}')
    echo -e "  ${ICON_ARROW} User '${SCI_USER_NAME}' exists (UID $SCI_USER_UID) — will reuse" >&2
  else
    SCI_USER_UID=$(find_available_uid)
    echo -e "  ${ICON_ARROW} User UID auto-selected: ${BOLD}$SCI_USER_UID${NC}" >&2
  fi

  # Auto-detect existing projects
  SCI_PROJECTS=()
  if [ -d "$SCI_PROJECTS_DIR" ]; then
    while IFS= read -r dir; do
      [ -d "$dir" ] && SCI_PROJECTS+=("$dir")
    done < <(find "$SCI_PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    if [ ${#SCI_PROJECTS[@]} -gt 0 ]; then
      echo -e "  ${ICON_ARROW} Found ${BOLD}${#SCI_PROJECTS[@]}${NC} projects in $SCI_PROJECTS_DIR" >&2
    fi
  fi

  # Confirm
  echo ""
  echo -e "  ${DIM}────────────────────────────────────────${NC}"
  echo -e "  User:       ${BOLD}$SCI_USER_NAME${NC} (UID $SCI_USER_UID)"
  echo -e "  Group:      ${BOLD}$SCI_GROUP_NAME${NC} (GID $SCI_GROUP_GID)"
  echo -e "  Main user:  $SCI_MAIN_USER"
  echo -e "  Projects:   $SCI_PROJECTS_DIR"
  echo -e "  Blocked:    ${SCI_BLOCKED_PATHS[*]}"
  echo -e "  Mode:       shared_ownership"
  if [ -n "$SCI_PROMPT_FILE" ]; then
    echo -e "  Prompt:     $SCI_PROMPT_FILE"
  fi
  echo -e "  ${DIM}────────────────────────────────────────${NC}"
  echo ""
  if ! confirm "Proceed with setup?"; then
    echo "  Aborted."
    return 0
  fi

  section "Setting up"

  sudo -v

  local step=0
  local failed=0

  # ── Step 1: Create group ──
  step=$((step + 1))
  step_start "Creating group '$SCI_GROUP_NAME'" $step $SETUP_TOTAL_STEPS
  if group_exists "$SCI_GROUP_NAME"; then
    step_skip "already exists"
  else
    if sudo dseditgroup -o create -i "$SCI_GROUP_GID" "$SCI_GROUP_NAME" 2>/dev/null; then
      step_ok
    else
      step_fail "dseditgroup failed"
      failed=$((failed + 1))
    fi
  fi

  # ── Step 2: Create user ──
  step=$((step + 1))
  step_start "Creating user '$SCI_USER_NAME'" $step $SETUP_TOTAL_STEPS
  if user_exists "$SCI_USER_NAME"; then
    step_skip "already exists"
  else
    if sudo dscl . -create "/Users/$SCI_USER_NAME" \
      && sudo dscl . -create "/Users/$SCI_USER_NAME" UserShell /bin/zsh \
      && sudo dscl . -create "/Users/$SCI_USER_NAME" RealName "Claude Dev" \
      && sudo dscl . -create "/Users/$SCI_USER_NAME" UniqueID "$SCI_USER_UID" \
      && sudo dscl . -create "/Users/$SCI_USER_NAME" PrimaryGroupID "$SCI_GROUP_GID" \
      && sudo dscl . -create "/Users/$SCI_USER_NAME" HomeDirectory "/Users/$SCI_USER_NAME" \
      && sudo dscl . -create "/Users/$SCI_USER_NAME" Password "*"; then
      step_ok
    else
      step_fail "dscl commands failed"
      failed=$((failed + 1))
    fi
  fi

  # ── Step 3: Home directory for isolated user ──
  step=$((step + 1))
  step_start "Setting up home directory" $step $SETUP_TOTAL_STEPS
  if [ ! -d "/Users/$SCI_USER_NAME" ]; then
    sudo mkdir -p "/Users/$SCI_USER_NAME"
  fi
  if sudo chown "$SCI_USER_NAME" "/Users/$SCI_USER_NAME" \
    && sudo chmod 755 "/Users/$SCI_USER_NAME"; then
    step_ok
  else
    step_fail
    failed=$((failed + 1))
  fi

  # ── Step 4: Lock main user home ──
  step=$((step + 1))
  step_start "Locking main user home directory" $step $SETUP_TOTAL_STEPS
  if sudo chmod 700 "$SCI_MAIN_HOME" \
    && sudo chmod +a "$SCI_USER_NAME allow search" "$SCI_MAIN_HOME" \
    && sudo chmod +a "$SCI_USER_NAME deny list,read,write,add_file,delete,add_subdirectory,readattr,writeattr,readextattr,writeextattr" "$SCI_MAIN_HOME"; then
    step_ok
  else
    step_fail "ACL on home directory failed"
    failed=$((failed + 1))
  fi

  # ── Step 5: Keychain ──
  step=$((step + 1))
  step_start "Configuring keychain" $step $SETUP_TOTAL_STEPS
  local keychain_path="/Users/$SCI_USER_NAME/Library/Keychains/${SCI_USER_NAME}.keychain"
  if [ -f "$keychain_path" ] || [ -f "${keychain_path}-db" ]; then
    if sudo -u "$SCI_USER_NAME" env HOME="/Users/$SCI_USER_NAME" \
        security default-keychain -s "${SCI_USER_NAME}.keychain" 2>/dev/null \
      && sudo -u "$SCI_USER_NAME" env HOME="/Users/$SCI_USER_NAME" \
        security unlock-keychain -p "" "${SCI_USER_NAME}.keychain" 2>/dev/null; then
      step_ok
    else
      step_warn "keychain exists but unlock failed — may need manual fix"
    fi
  else
    if sudo -u "$SCI_USER_NAME" env HOME="/Users/$SCI_USER_NAME" \
        security create-keychain -p "" "${SCI_USER_NAME}.keychain" \
      && sudo -u "$SCI_USER_NAME" env HOME="/Users/$SCI_USER_NAME" \
        security default-keychain -s "${SCI_USER_NAME}.keychain" \
      && sudo -u "$SCI_USER_NAME" env HOME="/Users/$SCI_USER_NAME" \
        security unlock-keychain -p "" "${SCI_USER_NAME}.keychain"; then
      step_ok
    else
      step_fail "keychain creation failed"
      failed=$((failed + 1))
    fi
  fi

  # ── Step 6: Open path to projects dir ──
  step=$((step + 1))
  step_start "Opening path to projects directory" $step $SETUP_TOTAL_STEPS
  mkdir -p "$SCI_PROJECTS_DIR" 2>/dev/null || sudo mkdir -p "$SCI_PROJECTS_DIR"
  if sudo chmod o+x "$SCI_MAIN_HOME/Documents" \
    && sudo chmod +a "$SCI_USER_NAME allow search" "$SCI_MAIN_HOME/Documents"; then
    step_ok
  else
    step_fail
    failed=$((failed + 1))
  fi

  # ── Step 7: Shared ownership ACL on projects dir ──
  step=$((step + 1))
  step_start "Applying shared ownership permissions" $step $SETUP_TOTAL_STEPS
  local acl="list,search,read,write,execute,add_file,add_subdirectory,delete,delete_child,readattr,writeattr,readextattr,writeextattr,file_inherit,directory_inherit"
  SCI_ACL="$acl"
  if sudo chmod -R +a "$SCI_USER_NAME allow $acl" "$SCI_PROJECTS_DIR" \
    && sudo chmod +ai "$SCI_USER_NAME allow $acl" "$SCI_PROJECTS_DIR" \
    && sudo chmod -R +a "$SCI_MAIN_USER allow $acl" "$SCI_PROJECTS_DIR" \
    && sudo chmod +ai "$SCI_MAIN_USER allow $acl" "$SCI_PROJECTS_DIR"; then
    step_ok
  else
    step_fail "ACL on projects directory failed"
    failed=$((failed + 1))
  fi

  # ── Step 8: Block security_data in all projects ──
  step=$((step + 1))
  step_start "Blocking protected folders" $step $SETUP_TOTAL_STEPS
  local block_count=0
  for project in "${SCI_PROJECTS[@]}"; do
    for blocked in "${SCI_BLOCKED_PATHS[@]}"; do
      local target="$project/$blocked"
      if [ -d "$target" ]; then
        sudo chmod +a "$SCI_USER_NAME deny list,search,readattr" "$target" 2>/dev/null
        block_count=$((block_count + 1))
      fi
    done
  done
  if [ $block_count -gt 0 ]; then
    step_ok
  else
    step_skip "no protected folders found yet"
  fi

  # ── Step 9: Install CLI tools ──
  step=$((step + 1))
  step_start "Installing CLI tools" $step $SETUP_TOTAL_STEPS

  # claude-shell — switch to isolated user (+ optional prompt file)
  cat > "$SCI_CONFIG_DIR/claude-shell" << SCRIPT
#!/bin/bash
source "$SCI_CONFIG_DIR/sci-config.sh"
if [ -n "\$SCI_PROMPT_FILE" ] && [ -f "\$SCI_PROMPT_FILE" ]; then
  open -a TextEdit "\$SCI_PROMPT_FILE"
fi
exec sudo launchctl asuser "\$SCI_USER_UID" sudo -u "\$SCI_USER_NAME" env HOME="/Users/\$SCI_USER_NAME" /bin/zsh
SCRIPT
  chmod +x "$SCI_CONFIG_DIR/claude-shell"

  # fixperms — reapply shared ownership ACL on all registered projects
  cat > "$SCI_CONFIG_DIR/fixperms" << 'OUTERSCRIPT'
#!/bin/bash
OUTERSCRIPT
  cat >> "$SCI_CONFIG_DIR/fixperms" << OUTERSCRIPT
source "$SCI_CONFIG_DIR/sci-config.sh"
PROJECTS_FILE="$SCI_CONFIG_DIR/projects.list"
BLOCKED_FILE="$SCI_CONFIG_DIR/blocked-paths.list"
OUTERSCRIPT
  cat >> "$SCI_CONFIG_DIR/fixperms" << 'INNERSCRIPT'

echo "Applying shared ownership ACL..."
sudo chmod -R +a "$SCI_USER_NAME allow $SCI_ACL" "$SCI_PROJECTS_DIR"
sudo chmod -R +a "$SCI_MAIN_USER allow $SCI_ACL" "$SCI_PROJECTS_DIR"

if [ -f "$PROJECTS_FILE" ] && [ -f "$BLOCKED_FILE" ]; then
  while IFS= read -r project; do
    [ -z "$project" ] && continue
    while IFS= read -r blocked; do
      [ -z "$blocked" ] && continue
      target="$project/$blocked"
      if [ -d "$target" ]; then
        sudo chmod +a "$SCI_USER_NAME deny list,search,readattr" "$target" 2>/dev/null
        echo "  Blocked: $(basename "$project")/$blocked"
      fi
    done < "$BLOCKED_FILE"
  done < "$PROJECTS_FILE"
fi
echo "Done."
INNERSCRIPT
  chmod +x "$SCI_CONFIG_DIR/fixperms"

  # clear-claude-temps — clean up .tmp.* files left by Claude Code atomic writes
  cat > "$SCI_CONFIG_DIR/clear-claude-temps" << 'SCRIPT'
#!/bin/bash
count=$(find . -name "*.tmp.*" -type f | wc -l | tr -d " ")
if [ "$count" -gt 0 ]; then
  find . -name "*.tmp.*" -type f -delete
  echo "✅ Cleaned $count .tmp files"
else
  echo "No .tmp files found."
fi
SCRIPT
  chmod +x "$SCI_CONFIG_DIR/clear-claude-temps"

  # xcode — open Xcode as isolated user
  cat > "$SCI_CONFIG_DIR/xcode" << SCRIPT
#!/bin/bash
source "$SCI_CONFIG_DIR/sci-config.sh"
exec sudo -u "\$SCI_USER_NAME" open -a Xcode "\$@"
SCRIPT
  chmod +x "$SCI_CONFIG_DIR/xcode"

  # Create prompt file if requested
  if [ -n "$SCI_PROMPT_FILE" ] && [ ! -f "$SCI_PROMPT_FILE" ]; then
    echo "# Prompts" > "$SCI_PROMPT_FILE"
  fi

  # Clean up any old SCI-ALIASES block from .zshrc
  local zshrc="$SCI_MAIN_HOME/.zshrc"
  if grep -q "# SCI-ALIASES-START" "$zshrc" 2>/dev/null; then
    sed -i '' '/# SCI-ALIASES-START/,/# SCI-ALIASES-END/d' "$zshrc"
  fi

  step_ok

  # ── Step 11: Save config ──
  step=$((step + 1))
  step_start "Saving configuration" $step $SETUP_TOTAL_STEPS
  config_write
  step_ok

  # ── Verification ──
  section "Running verification"
  source "$SCI_DIR/lib/verify.sh"
  local verify_result
  run_verify_checks
  verify_result=$?

  if [ $failed -eq 0 ] && [ $verify_result -eq 0 ]; then
    success_banner "Setup complete" "Start: claude-shell → cd /path/to/project → claude"
  else
    error_banner "Setup completed with issues" "Run 'sci verify' to see details, or 'sci repair' to fix."
  fi

  echo -e "  ${DIM}Next steps:${NC}"
  echo -e "  ${DIM}1.${NC} claude-shell"
  echo -e "  ${DIM}2.${NC} Install Claude Code inside the shell (first time only):"
  echo -e "     ${DIM}curl -fsSL https://claude.ai/install.sh | sh${NC}"
  echo -e "  ${DIM}3.${NC} cd /path/to/project && claude"
  echo ""
}
