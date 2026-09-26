#!/bin/bash
# SCI UI helpers — colors, banners, progress

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ICON_OK="✓"
ICON_FAIL="✗"
ICON_WARN="⚠"
ICON_ARROW="→"
ICON_LOCK="🔒"

sci_header() {
  echo ""
  echo -e "  ${CYAN}┌─────────────────────────────────────────┐${NC}"
  echo -e "  ${CYAN}│${NC}  ${ICON_LOCK} ${BOLD}SCI — Safe Claude Integration${NC}       ${CYAN}│${NC}"
  echo -e "  ${CYAN}│${NC}  ${DIM}v${SCI_VERSION:-1.0.0}${NC}                                 ${CYAN}│${NC}"
  echo -e "  ${CYAN}└─────────────────────────────────────────┘${NC}"
  echo ""
}

step_start() {
  local msg="$1" current="$2" total="$3"
  printf "  ${DIM}[%d/%d]${NC} %s" "$current" "$total" "$msg"
}

step_ok() {
  echo -e " ${GREEN}${ICON_OK}${NC}"
}

step_fail() {
  local reason="${1:-}"
  echo -e " ${RED}${ICON_FAIL}${NC}"
  [ -n "$reason" ] && echo -e "        ${RED}${reason}${NC}"
}

step_skip() {
  local reason="${1:-already exists}"
  echo -e " ${YELLOW}skip${NC} ${DIM}(${reason})${NC}"
}

step_warn() {
  echo -e " ${YELLOW}${ICON_WARN}${NC} ${DIM}$1${NC}"
}

check_ok() {
  echo -e "  ${GREEN}${ICON_OK}${NC} $1"
}

check_fail() {
  echo -e "  ${RED}${ICON_FAIL}${NC} $1"
}

check_warn() {
  echo -e "  ${YELLOW}${ICON_WARN}${NC} $1"
}

prompt_value() {
  local label="$1" default="${2:-}" result
  if [ -n "$default" ]; then
    printf "  ${ICON_ARROW} %s ${DIM}[%s]${NC}: " "$label" "$default" >&2
    read -r result
    echo "${result:-$default}"
  else
    printf "  ${ICON_ARROW} %s: " "$label" >&2
    read -r result
    echo "$result"
  fi
}

confirm() {
  local answer
  printf "  ${ICON_ARROW} %s ${DIM}[y/N]${NC}: " "$1"
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

section() {
  echo ""
  echo -e "  ${BOLD}$1${NC}"
  echo ""
}

success_banner() {
  echo ""
  echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${GREEN}${ICON_OK}${NC} ${BOLD}$1${NC}"
  [ -n "${2:-}" ] && echo -e "     ${DIM}$2${NC}"
  echo -e "  ${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

error_banner() {
  echo ""
  echo -e "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${RED}${ICON_FAIL}${NC} ${BOLD}$1${NC}"
  [ -n "${2:-}" ] && echo -e "     ${DIM}$2${NC}"
  echo -e "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}
