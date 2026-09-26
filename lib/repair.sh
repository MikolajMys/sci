#!/bin/bash
# SCI Repair — diagnose and fix after macOS update
# Reads config, checks what survived, restores what didn't

run_repair() {
  sci_header

  if ! config_load; then
    error_banner "No SCI config found" "Run 'sci setup' first — repair needs existing config."
    return 1
  fi

  section "Diagnosing"

  # Collect what's broken
  local needs_user=0
  local needs_group=0
  local needs_home=0
  local needs_keychain=0
  local needs_home_acl=0
  local needs_docs_acl=0
  local needs_projects_acl=0
  local needs_blocked=0

  # 1. Group
  if group_exists "$SCI_GROUP_NAME"; then
    check_ok "Group '$SCI_GROUP_NAME' exists"
  else
    check_fail "Group '$SCI_GROUP_NAME' missing"
    needs_group=1
  fi

  # 2. User
  if user_exists "$SCI_USER_NAME"; then
    local actual_uid
    actual_uid=$(dscl . -read "/Users/$SCI_USER_NAME" UniqueID 2>/dev/null | awk '{print $2}')
    if [ "$actual_uid" = "$SCI_USER_UID" ]; then
      check_ok "User '$SCI_USER_NAME' exists (UID $actual_uid)"
    else
      check_fail "User '$SCI_USER_NAME' exists but wrong UID ($actual_uid, expected $SCI_USER_UID)"
      needs_user=1
    fi
  else
    check_fail "User '$SCI_USER_NAME' missing (deleted by macOS update)"
    needs_user=1
  fi

  # 3. Home directory
  if [ -d "/Users/$SCI_USER_NAME" ]; then
    check_ok "Home directory /Users/$SCI_USER_NAME exists"
  else
    check_fail "Home directory missing"
    needs_home=1
  fi

  # 4. Keychain
  local kc_path="/Users/$SCI_USER_NAME/Library/Keychains/${SCI_USER_NAME}.keychain"
  if [ -f "$kc_path" ] || [ -f "${kc_path}-db" ]; then
    check_ok "Keychain file exists"
  else
    check_fail "Keychain file missing"
    needs_keychain=1
  fi

  # 5. Home ACL — can claude-dev list home? (should NOT be able to)
  if user_exists "$SCI_USER_NAME"; then
    if sudo -u "$SCI_USER_NAME" ls "$SCI_MAIN_HOME" &>/dev/null; then
      check_fail "Home ACL broken — $SCI_USER_NAME can list home"
      needs_home_acl=1
    else
      check_ok "Home ACL intact"
    fi
  else
    # User doesn't exist yet — ACL will be broken after recreating
    check_warn "Home ACL — will check after user is restored"
    needs_home_acl=1
  fi

  # 6. Documents traversal
  if user_exists "$SCI_USER_NAME"; then
    if sudo -u "$SCI_USER_NAME" ls "$SCI_PROJECTS_DIR" &>/dev/null; then
      check_ok "Projects directory accessible"
    else
      check_fail "Projects directory not accessible"
      needs_docs_acl=1
      needs_projects_acl=1
    fi
  else
    check_warn "Projects ACL — will check after user is restored"
    needs_docs_acl=1
    needs_projects_acl=1
  fi

  # 7. security_data
  local blocked_broken=0
  if user_exists "$SCI_USER_NAME"; then
    for project in "${SCI_PROJECTS[@]}"; do
      for blocked in "${SCI_BLOCKED_PATHS[@]}"; do
        local target="$project/$blocked"
        if [ -d "$target" ]; then
          if sudo -u "$SCI_USER_NAME" ls "$target" &>/dev/null; then
            blocked_broken=$((blocked_broken + 1))
          fi
        fi
      done
    done
  fi
  if [ $blocked_broken -gt 0 ]; then
    check_fail "$blocked_broken protected folder(s) accessible"
    needs_blocked=1
  else
    if user_exists "$SCI_USER_NAME"; then
      check_ok "Protected folders blocked"
    else
      check_warn "Protected folders — will check after user is restored"
      needs_blocked=1
    fi
  fi

  # Summary
  local total_fixes=$((needs_group + needs_user + needs_home + needs_keychain + needs_home_acl + needs_docs_acl + needs_projects_acl + needs_blocked))

  echo ""
  if [ $total_fixes -eq 0 ]; then
    success_banner "Everything looks good" "Nothing to repair."
    return 0
  fi

  echo -e "  ${YELLOW}Found $total_fixes issue(s) to fix.${NC}"
  echo ""
  if ! confirm "Proceed with repair?"; then
    echo "  Aborted."
    return 0
  fi

  section "Repairing"

  local step=0
  local repair_steps=$total_fixes
  local failed=0

  # ── Fix group ──
  if [ $needs_group -eq 1 ]; then
    step=$((step + 1))
    step_start "Recreating group '$SCI_GROUP_NAME'" $step $repair_steps
    if sudo dseditgroup -o create -i "$SCI_GROUP_GID" "$SCI_GROUP_NAME" 2>/dev/null; then
      step_ok
    else
      step_fail "dseditgroup failed"
      failed=$((failed + 1))
    fi
  fi

  # ── Fix user ──
  if [ $needs_user -eq 1 ]; then
    step=$((step + 1))
    step_start "Recreating user '$SCI_USER_NAME'" $step $repair_steps

    # If user exists with wrong UID, delete first
    if user_exists "$SCI_USER_NAME"; then
      sudo dscl . -delete "/Users/$SCI_USER_NAME" 2>/dev/null
    fi

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

  # ── Fix home directory ──
  if [ $needs_home -eq 1 ]; then
    step=$((step + 1))
    step_start "Creating home directory" $step $repair_steps
    if sudo mkdir -p "/Users/$SCI_USER_NAME" \
      && sudo chown "$SCI_USER_NAME" "/Users/$SCI_USER_NAME" \
      && sudo chmod 755 "/Users/$SCI_USER_NAME"; then
      step_ok
    else
      step_fail
      failed=$((failed + 1))
    fi
  elif [ $needs_user -eq 1 ]; then
    # User was recreated — fix ownership on existing home dir
    sudo chown "$SCI_USER_NAME" "/Users/$SCI_USER_NAME" 2>/dev/null
    sudo chmod 755 "/Users/$SCI_USER_NAME" 2>/dev/null
  fi

  # ── Fix keychain ──
  if [ $needs_keychain -eq 1 ]; then
    step=$((step + 1))
    step_start "Creating keychain" $step $repair_steps
    if sudo -u "$SCI_USER_NAME" env HOME="/Users/$SCI_USER_NAME" \
        security create-keychain -p "" "${SCI_USER_NAME}.keychain" 2>/dev/null \
      && sudo -u "$SCI_USER_NAME" env HOME="/Users/$SCI_USER_NAME" \
        security default-keychain -s "${SCI_USER_NAME}.keychain" 2>/dev/null \
      && sudo -u "$SCI_USER_NAME" env HOME="/Users/$SCI_USER_NAME" \
        security unlock-keychain -p "" "${SCI_USER_NAME}.keychain" 2>/dev/null; then
      step_ok
    else
      step_fail
      failed=$((failed + 1))
    fi
  else
    # Keychain file exists but user was recreated — reconnect
    if [ $needs_user -eq 1 ]; then
      sudo -u "$SCI_USER_NAME" env HOME="/Users/$SCI_USER_NAME" \
        security default-keychain -s "${SCI_USER_NAME}.keychain" 2>/dev/null
      sudo -u "$SCI_USER_NAME" env HOME="/Users/$SCI_USER_NAME" \
        security unlock-keychain -p "" "${SCI_USER_NAME}.keychain" 2>/dev/null
    fi
  fi

  # ── Fix home ACL ──
  if [ $needs_home_acl -eq 1 ]; then
    step=$((step + 1))
    step_start "Restoring home directory ACL" $step $repair_steps
    if sudo chmod 700 "$SCI_MAIN_HOME" \
      && sudo chmod +a "$SCI_USER_NAME allow search" "$SCI_MAIN_HOME" \
      && sudo chmod +a "$SCI_USER_NAME deny list,read,write,add_file,delete,add_subdirectory,readattr,writeattr,readextattr,writeextattr" "$SCI_MAIN_HOME"; then
      step_ok
    else
      step_fail "Home ACL failed"
      failed=$((failed + 1))
    fi
  fi

  # ── Fix Documents traversal ──
  if [ $needs_docs_acl -eq 1 ]; then
    step=$((step + 1))
    step_start "Restoring Documents traversal" $step $repair_steps
    if sudo chmod o+x "$SCI_MAIN_HOME/Documents" \
      && sudo chmod +a "$SCI_USER_NAME allow search" "$SCI_MAIN_HOME/Documents"; then
      step_ok
    else
      step_fail
      failed=$((failed + 1))
    fi
  fi

  # ── Fix projects ACL ──
  if [ $needs_projects_acl -eq 1 ]; then
    step=$((step + 1))
    step_start "Restoring projects permissions" $step $repair_steps
    local acl="$SCI_ACL"
    if sudo chmod -R +a "$SCI_USER_NAME allow $acl" "$SCI_PROJECTS_DIR" \
      && sudo chmod +ai "$SCI_USER_NAME allow $acl" "$SCI_PROJECTS_DIR" \
      && sudo chmod -R +a "$SCI_MAIN_USER allow $acl" "$SCI_PROJECTS_DIR" \
      && sudo chmod +ai "$SCI_MAIN_USER allow $acl" "$SCI_PROJECTS_DIR"; then
      step_ok
    else
      step_fail "Projects ACL failed"
      failed=$((failed + 1))
    fi
  fi

  # ── Fix blocked folders ──
  if [ $needs_blocked -eq 1 ]; then
    step=$((step + 1))
    step_start "Re-blocking protected folders" $step $repair_steps
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
    step_ok
  fi

  # Update config timestamp
  config_touch

  # ── Run verification ──
  section "Post-repair verification"
  source "$SCI_DIR/lib/verify.sh"
  local verify_result
  run_verify_checks
  verify_result=$?

  if [ $failed -eq 0 ] && [ $verify_result -eq 0 ]; then
    success_banner "Repair complete — all checks passed" "Start: claude-shell → cd /path/to/project → claude"
  else
    error_banner "Repair completed with issues" "Some checks still failing — review output above."
  fi
}
