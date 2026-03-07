#!/usr/bin/env bash
# kban-autorun.sh — Run Claude on active kban tickets automatically
#
# Fetches tickets from the "ready" and/or "doing" lanes, feeds each one to
# `claude --dangerously-skip-permissions --print`, and optionally marks them
# done on success.
#
# Usage: ./kban-autorun.sh [OPTIONS]
#
# Examples:
#   ./kban-autorun.sh                          # Process all ready + doing tickets
#   ./kban-autorun.sh --one                    # Process only the next ready ticket
#   ./kban-autorun.sh --dry-run                # Preview without executing
#   ./kban-autorun.sh --mark-done              # Auto-mark tickets done after Claude
#   ./kban-autorun.sh --lane ready             # Only process ready lane tickets
#   ./kban-autorun.sh --log-dir ./logs         # Save Claude output to ./logs/
#   ./kban-autorun.sh --one --mark-done        # CI-friendly: one ticket at a time

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
STRIP_ANSI='s/\x1b\[[0-9;]*[mK]//g'   # sed expression to strip ANSI codes

# ── Defaults ──────────────────────────────────────────────────────────────────
CLAUDE_CMD="${CLAUDE_CMD:-claude}"
CLAUDE_FLAGS="--dangerously-skip-permissions --print"
LANES=("ready" "doing")
DRY_RUN=false
MARK_DONE=false
ONE_ONLY=false
LOG_DIR=""
FAIL_FAST=false

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { printf "${BLUE}[kban-autorun]${NC} %s\n"   "$*" >&2; }
ok()   { printf "${GREEN}[kban-autorun]${NC} %s\n"  "$*" >&2; }
warn() { printf "${YELLOW}[kban-autorun]${NC} %s\n" "$*" >&2; }
err()  { printf "${RED}[kban-autorun]${NC} %s\n"    "$*" >&2; }
sep()  { printf "${CYAN}%s${NC}\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2; }

usage() {
  cat <<EOF
${BOLD}kban-autorun${NC} — Run Claude on active kban tickets

${BOLD}Usage:${NC}
  $(basename "$0") [OPTIONS]

${BOLD}Options:${NC}
  --one              Process only the next single actionable ticket (kban next)
  --mark-done        Move ticket to done lane after Claude succeeds
  --lane <lane>      Restrict to one lane: ready, doing, backlog (repeatable)
  --log-dir <dir>    Save each ticket's Claude output to <dir>/<ID>-<ts>.log
  --fail-fast        Stop after the first ticket failure
  --dry-run          Show what would run without executing anything
  -h, --help         Show this help

${BOLD}Environment:${NC}
  CLAUDE_CMD         Override the claude binary path (default: claude)

${BOLD}Examples:${NC}
  $(basename "$0")                        # All ready + doing tickets
  $(basename "$0") --one --mark-done      # Next ticket, mark done on success
  $(basename "$0") --lane ready --dry-run # Preview ready-lane tickets
  $(basename "$0") --log-dir ./logs       # Save output to ./logs/
EOF
  exit 0
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    err "Required command not found: '$cmd'"
    err "Install it and try again."
    exit 1
  fi
}

# Strip ANSI colour codes from a string
strip_ansi() { sed "$STRIP_ANSI"; }

# ── Argument Parsing ──────────────────────────────────────────────────────────
CUSTOM_LANES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true;  shift ;;
    --mark-done)  MARK_DONE=true; shift ;;
    --one)        ONE_ONLY=true; shift ;;
    --fail-fast)  FAIL_FAST=true; shift ;;
    --lane)       [[ $# -lt 2 ]] && { err "--lane requires a value"; exit 1; }
                  CUSTOM_LANES+=("$2"); shift 2 ;;
    --log-dir)    [[ $# -lt 2 ]] && { err "--log-dir requires a value"; exit 1; }
                  LOG_DIR="$2"; shift 2 ;;
    -h|--help)    usage ;;
    *)            err "Unknown option: $1"; usage ;;
  esac
done

[[ ${#CUSTOM_LANES[@]} -gt 0 ]] && LANES=("${CUSTOM_LANES[@]}")

# ── Pre-flight Checks ─────────────────────────────────────────────────────────
require_cmd kban
require_cmd "$CLAUDE_CMD"

if [[ -n "$LOG_DIR" ]]; then
  mkdir -p "$LOG_DIR"
  log "Logs will be saved to: $LOG_DIR"
fi

$DRY_RUN && warn "DRY RUN mode — nothing will be executed"

# ── Ticket Collection ─────────────────────────────────────────────────────────
collect_tickets() {
  if $ONE_ONLY; then
    # kban next: prints just the ID, exits 1 if nothing available
    local next_id
    next_id=$(kban next 2>/dev/null | strip_ansi | grep -oE '[A-Z]+-[0-9]+' | head -1 || true)
    if [[ -z "$next_id" ]]; then
      warn "No actionable ticket found via 'kban next' (ready lane, deps met)"
      exit 0
    fi
    echo "$next_id"
  else
    local lane
    for lane in "${LANES[@]}"; do
      # kban list <lane>: one ID per line, may have ANSI codes + [BLOCKED] suffix
      kban list "$lane" 2>/dev/null \
        | strip_ansi \
        | grep -oE '^[A-Z]+-[0-9]+' \
        || true
    done
  fi
}

# ── Prompt Builder ────────────────────────────────────────────────────────────
build_prompt() {
  local ticket_id="$1"
  local ticket_content
  # kban show includes lane header, separator, then full Markdown+frontmatter
  ticket_content=$(kban show "$ticket_id" 2>/dev/null | strip_ansi)

  cat <<PROMPT
You are an autonomous agent working on a kban project management ticket.
Your job is to implement everything described in the ticket completely and
to a high standard — not to summarise or plan, but to actually do the work.

═══════════════════════════════════════════════════════════════
TICKET: ${ticket_id}
═══════════════════════════════════════════════════════════════
${ticket_content}
═══════════════════════════════════════════════════════════════

WORKING INSTRUCTIONS:
• Read the ticket carefully, then execute all tasks described.
• Leverage available agents and skills — spawn sub-agents for independent
  subtasks, run things in parallel where possible, use specialised skills
  (e.g. claude-api, session-start-hook, simplify) when they match the work.
• Write clean, minimal, well-tested code. Avoid over-engineering.
• When the work is genuinely complete, output a concise summary of exactly
  what you did so the automation layer can confirm success.
• Do NOT call 'kban done' — the caller script handles lane transitions.
PROMPT
}

# ── Single Ticket Runner ──────────────────────────────────────────────────────
run_ticket() {
  local ticket_id="$1"
  local prompt exit_code=0

  # Build the prompt (reads full ticket content)
  prompt=$(build_prompt "$ticket_id")

  # Move ready → doing so the board reflects in-progress state
  if kban list ready 2>/dev/null | strip_ansi | grep -q "^${ticket_id}"; then
    log "Moving ${ticket_id} → doing"
    if ! $DRY_RUN; then
      kban start "$ticket_id" 2>/dev/null \
        || warn "Could not move ${ticket_id} to doing (may already be there)"
    fi
  fi

  if $DRY_RUN; then
    warn "[DRY RUN] Would run: $CLAUDE_CMD $CLAUDE_FLAGS"
    warn "[DRY RUN] Prompt (first 15 lines):"
    echo "$prompt" | head -15 | sed 's/^/  │ /' >&2
    return 0
  fi

  # Run Claude, tee to log file if requested
  if [[ -n "$LOG_DIR" ]]; then
    local ts log_file
    ts=$(date +%Y%m%d-%H%M%S)
    log_file="${LOG_DIR}/${ticket_id}-${ts}.log"
    log "Streaming output → ${log_file}"
    echo "$prompt" | "$CLAUDE_CMD" $CLAUDE_FLAGS 2>&1 | tee "$log_file" || exit_code=${PIPESTATUS[1]}
  else
    echo "$prompt" | "$CLAUDE_CMD" $CLAUDE_FLAGS || exit_code=$?
  fi

  if [[ $exit_code -eq 0 ]]; then
    ok "Claude finished: ${ticket_id}"
    if $MARK_DONE; then
      log "Marking ${ticket_id} as done"
      kban done "$ticket_id" 2>/dev/null \
        || warn "Could not mark ${ticket_id} as done (check its current lane)"
    fi
  else
    err "Claude exited with code ${exit_code} for ticket: ${ticket_id}"
    return "$exit_code"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  log "Collecting tickets from lane(s): ${LANES[*]}"

  # Collect unique IDs (dedup in case a ticket somehow appears in multiple lanes)
  local ticket_ids=()
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    # Skip duplicates
    local dup=false
    local existing
    for existing in "${ticket_ids[@]+"${ticket_ids[@]}"}"; do
      [[ "$existing" == "$id" ]] && { dup=true; break; }
    done
    $dup || ticket_ids+=("$id")
  done < <(collect_tickets)

  if [[ ${#ticket_ids[@]} -eq 0 ]]; then
    warn "No tickets found in lane(s): ${LANES[*]}"
    exit 0
  fi

  log "Found ${#ticket_ids[@]} ticket(s): ${ticket_ids[*]}"

  local failed=0 processed=0
  for id in "${ticket_ids[@]}"; do
    echo >&2
    sep
    log "Ticket ${id}  ($(( ++processed ))/${#ticket_ids[@]})"
    sep

    if run_ticket "$id"; then
      : # success counted implicitly
    else
      (( failed++ )) || true
      if $FAIL_FAST; then
        err "Stopping early (--fail-fast)"
        break
      fi
    fi
  done

  echo >&2
  sep
  if [[ $failed -gt 0 ]]; then
    err "${failed}/${#ticket_ids[@]} ticket(s) failed"
    exit 1
  else
    ok "All ${#ticket_ids[@]} ticket(s) processed successfully"
  fi
}

main
