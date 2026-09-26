#!/bin/bash
# SCI Verify — verification checks

run_verify() {
  sci_header
  section "Verification"

  if ! config_load; then
    error_banner "No SCI config found" "Run 'sci setup' first."
    return 1
  fi

  run_verify_checks
}

# Shared by setup (inline) and verify (standalone)
# Returns 0 if all critical checks pass, 1 otherwise
run_verify_checks() {
  if ! config_load 2>/dev/null; then
    check_fail "Config not found — run 'sci setup'"
    return 1
  fi

  local failures=0

  # 1. User exists in dscl
  if user_exists "$SCI_USER_NAME"; then
    local actual_uid
    actual_uid=$(dscl . -read "/Users/$SCI_USER_NAME" UniqueID 2>/dev/null | awk '{print $2}')
    if [ "$actual_uid" = "$SCI_USER_UID" ]; then
      check_ok "$SCI_USER_NAME exists (UID $actual_uid)"
    else
      check_fail "$SCI_USER_NAME exists but UID mismatch (expected $SCI_USER_UID, got $actual_uid)"
      failures=$((failures + 1))
    fi
  else
    check_fail "$SCI_USER_NAME does not exist — run 'sci repair'"
    failures=$((failures + 1))
  fi

  # 2. Group exists
  if group_exists "$SCI_GROUP_NAME"; then
    check_ok "Group '$SCI_GROUP_NAME' exists"
  else
    check_fail "Group '$SCI_GROUP_NAME' does not exist"
    failures=$((failures + 1))
  fi

  # 3. Cannot list main user home
  if sudo -u "$SCI_USER_NAME" ls "$SCI_MAIN_HOME" &>/dev/null; then
    check_fail "$SCI_USER_NAME CAN list $SCI_MAIN_HOME — should be blocked"
    failures=$((failures + 1))
  else
    check_ok "$SCI_USER_NAME cannot list main user home"
  fi

  # 4. Cannot read files outside projects
  if sudo -u "$SCI_USER_NAME" cat "$SCI_MAIN_HOME/.zshrc" &>/dev/null; then
    check_fail "$SCI_USER_NAME CAN read files outside projects — should be blocked"
    failures=$((failures + 1))
  else
    check_ok "$SCI_USER_NAME cannot read files outside projects"
  fi

  # 5. CAN access projects directory
  if sudo -u "$SCI_USER_NAME" ls "$SCI_PROJECTS_DIR" &>/dev/null; then
    check_ok "$SCI_USER_NAME can access projects directory"
  else
    check_fail "$SCI_USER_NAME cannot access projects directory — ACL broken"
    failures=$((failures + 1))
  fi

  # 6. Shared ownership — can write in projects
  local test_file="$SCI_PROJECTS_DIR/.sci-write-test-$$"
  if sudo -u "$SCI_USER_NAME" touch "$test_file" 2>/dev/null; then
    # Can main user also access it?
    if cat "$test_file" &>/dev/null; then
      check_ok "Shared ownership works (both users can access files)"
    else
      check_warn "claude-dev can write but main user can't read — ACL inheritance issue"
    fi
    rm -f "$test_file" 2>/dev/null || sudo rm -f "$test_file" 2>/dev/null
  else
    check_fail "$SCI_USER_NAME cannot write to projects directory"
    failures=$((failures + 1))
  fi

  # 7. security_data blocked per project
  local blocked_ok=0
  local blocked_fail=0
  for project in "${SCI_PROJECTS[@]}"; do
    for blocked in "${SCI_BLOCKED_PATHS[@]}"; do
      local target="$project/$blocked"
      if [ -d "$target" ]; then
        if sudo -u "$SCI_USER_NAME" ls "$target" &>/dev/null; then
          blocked_fail=$((blocked_fail + 1))
        else
          blocked_ok=$((blocked_ok + 1))
        fi
      fi
    done
  done
  if [ $blocked_fail -gt 0 ]; then
    check_fail "$blocked_fail protected folder(s) accessible — should be blocked"
    failures=$((failures + 1))
  elif [ $blocked_ok -gt 0 ]; then
    check_ok "All $blocked_ok protected folder(s) blocked"
  else
    check_warn "No protected folders found to test"
  fi

  # 8. Keychain
  local keychain_path="/Users/$SCI_USER_NAME/Library/Keychains/${SCI_USER_NAME}.keychain"
  if [ -f "$keychain_path" ] || [ -f "${keychain_path}-db" ]; then
    check_ok "Keychain file exists"
  else
    check_fail "Keychain file not found"
    failures=$((failures + 1))
  fi

  # 9. No GUI login (Password = *)
  local pw_check
  pw_check=$(sudo dscl . -read "/Users/$SCI_USER_NAME" Password 2>/dev/null | awk '{print $2}')
  if [ "$pw_check" = "*" ]; then
    check_ok "GUI login disabled (Password = *)"
  else
    check_warn "Password field is not '*' — GUI login may be possible"
  fi

  # 10. Other-read audit — advisory only
  local other_readable
  other_readable=$(find "$SCI_MAIN_HOME" -maxdepth 1 -perm -o+r -not -name "." 2>/dev/null | head -5)
  if [ -n "$other_readable" ]; then
    check_warn "Some files in home dir have other-read — run 'sci harden' to protect them"
  else
    check_ok "No other-readable files in home directory root"
  fi

  echo ""
  if [ $failures -eq 0 ]; then
    echo -e "  ${GREEN}All critical checks passed.${NC}"
  else
    echo -e "  ${RED}$failures check(s) failed.${NC}"
  fi

  return $failures
}

run_status() {
  sci_header

  if ! config_load; then
    echo "  No config found. Run 'sci setup'."
    return 1
  fi

  section "Status"

  echo -e "  User:        ${BOLD}$SCI_USER_NAME${NC} (UID $SCI_USER_UID)"
  if user_exists "$SCI_USER_NAME"; then
    echo -e "               ${GREEN}${ICON_OK} exists in dscl${NC}"
  else
    echo -e "               ${RED}${ICON_FAIL} missing — run 'sci repair'${NC}"
  fi

  echo -e "  Group:       $SCI_GROUP_NAME (GID $SCI_GROUP_GID)"
  echo -e "  Main user:   $SCI_MAIN_USER"
  echo -e "  Projects:    $SCI_PROJECTS_DIR"
  echo -e "  Mode:        $SCI_PERM_MODE"
  echo -e "  Registered:  ${#SCI_PROJECTS[@]} project(s)"
  for p in "${SCI_PROJECTS[@]}"; do
    echo -e "               ${DIM}$(basename "$p")${NC}"
  done
  echo -e "  Blocked:     ${SCI_BLOCKED_PATHS[*]}"
  echo -e "  Config:      $SCI_CONFIG_FILE"
  echo -e "  Last update: $SCI_UPDATED"
  echo ""
}
