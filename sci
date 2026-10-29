#!/bin/bash
set -euo pipefail

SCI_DIR="$(cd "$(dirname "$0")" && pwd)"
SCI_VERSION="1.0.0"

source "$SCI_DIR/lib/ui.sh"

show_help() {
  echo ""
  sci_header
  echo "  Usage: sci <command>"
  echo ""
  echo "  Commands:"
  echo "    setup            Full interactive setup on a new machine"
  echo "    repair           Diagnose and fix after macOS update"
  echo "    verify           Run all verification checks"
  echo "    status           Show current state overview"
  echo "    add-project      Add a project directory to isolation"
  echo "    remove-project   Remove a project from isolation"
  echo "    hooks install    Install/update Claude Code hooks"
  echo "    uninstall        Remove everything SCI created"
  echo "    shell          Enter isolated user shell"
  echo "    fix            Fix file permissions after work session"
  echo "    path [name]    Print projects directory (or specific project path)"
  echo ""
  echo "  Version: $SCI_VERSION"
  echo ""
}

case "${1:-}" in
  setup)
    source "$SCI_DIR/lib/config.sh"
    source "$SCI_DIR/lib/setup.sh"
    run_setup
    ;;
  repair)
    source "$SCI_DIR/lib/config.sh"
    source "$SCI_DIR/lib/repair.sh"
    run_repair
    ;;
  verify)
    source "$SCI_DIR/lib/config.sh"
    source "$SCI_DIR/lib/verify.sh"
    run_verify
    ;;
  status)
    source "$SCI_DIR/lib/config.sh"
    source "$SCI_DIR/lib/verify.sh"
    run_status
    ;;
  add-project)
    source "$SCI_DIR/lib/config.sh"
    source "$SCI_DIR/lib/projects.sh"
    add_project "${2:-}"
    ;;
  remove-project)
    source "$SCI_DIR/lib/config.sh"
    source "$SCI_DIR/lib/projects.sh"
    remove_project "${2:-}"
    ;;
  hooks)
    source "$SCI_DIR/lib/config.sh"
    source "$SCI_DIR/lib/hooks.sh"
    run_hooks "${2:-}"
    ;;
  uninstall)
    source "$SCI_DIR/lib/config.sh"
    source "$SCI_DIR/lib/uninstall.sh"
    run_uninstall
    ;;
  -h|--help|help|"")
    show_help
    ;;
  shell)
    source "$SCI_DIR/lib/config.sh"
    config_load
    if [ -n "$SCI_PROMPT_FILE" ] && [ -f "$SCI_PROMPT_FILE" ]; then
      open -a TextEdit "$SCI_PROMPT_FILE"
    fi
    exec sudo launchctl asuser "$SCI_USER_UID" sudo -u "$SCI_USER_NAME" env HOME="/Users/$SCI_USER_NAME" /bin/zsh
    ;;
  fix)
    source "$SCI_DIR/lib/config.sh"
    config_load
    sudo chmod -R +a "$SCI_USER_NAME allow $SCI_ACL" "$SCI_PROJECTS_DIR"
    sudo chmod -R +a "$SCI_MAIN_USER allow $SCI_ACL" "$SCI_PROJECTS_DIR"
    for d in "$SCI_PROJECTS_DIR"/*/security_data; do
      [ -d "$d" ] && sudo chmod +a "$SCI_USER_NAME deny list,search,readattr" "$d"
    done
    echo "  ✓ Permissions fixed"
    ;;
  cd)
    echo "  cd nie działa jako subkomenda (subprocess nie zmieni katalogu parenta)."
    echo "  Użyj: cd \$(sci path ${2:-})"
    ;;
  path)
    source "$SCI_DIR/lib/config.sh"
    config_load
    if [ -n "${2:-}" ]; then
      echo "$SCI_PROJECTS_DIR/$2"
    else
      echo "$SCI_PROJECTS_DIR"
    fi
    ;;
  *)
    echo "  Unknown command: $1"
    show_help
    exit 1
    ;;
esac
