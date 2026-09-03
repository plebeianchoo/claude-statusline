#!/usr/bin/env bash
# Claude Code statusline, two lines:
#   1: brand + model (matching color) · session cost · context used · 5h rate limit bar
#   2: cwd · git branch
# Segments are joined with a straight powerline-style divider (│).
#
# Env vars:
#   CLAUDE_STATUSLINE_ASCII=1     force plain ASCII (no color, no unicode bars/separators)
#   COLORTERM=truecolor|24bit     enables the 24-bit gradient bars (set by most modern terminals)
#
# Rendering cascades three tiers: truecolor gradient -> 256-color gradient -> ASCII,
# picked once at the top and used for every colored segment below.
set -uo pipefail

USE_ASCII="${CLAUDE_STATUSLINE_ASCII:-0}"
USE_TRUECOLOR=0
if [[ "${COLORTERM:-}" == "truecolor" || "${COLORTERM:-}" == "24bit" ]]; then
  USE_TRUECOLOR=1
fi

input=$(cat)

# One jq call for every field, in a fixed order matched by the reads below —
# avoids spawning a separate jq process per field on every render.
parsed=$(jq -r '
  (.workspace.current_dir // .cwd // "?"),
  (.model.display_name // .model.id // "?"),
  (.cost.total_cost_usd // 0),
  (.context_window.remaining_percentage // ""),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.five_hour.resets_at // "")
' <<<"$input")

{
  IFS= read -r raw_dir
  IFS= read -r model
  IFS= read -r cost
  IFS= read -r remaining
  IFS= read -r five_hour
  IFS= read -r five_reset
} <<<"$parsed"

dir=${raw_dir/#$HOME/\~}
cost_fmt=$(printf '$%.2f' "$cost")

if [[ "$USE_ASCII" == "1" ]]; then
  RESET='' DIM='' CYAN='' GREEN='' YELLOW='' RED='' MAGENTA='' GOLD='' PURPLE=''
else
  RESET='\033[0m'
  DIM='\033[2m'
  CYAN='\033[36m'
  GREEN='\033[32m'
  YELLOW='\033[33m'
  RED='\033[31m'
  MAGENTA='\033[35m'
  GOLD='\033[38;5;220m'
  # Anthropic brand purple (#7266EA), degrading by tier.
  if (( USE_TRUECOLOR )); then
    PURPLE='\033[38;2;114;102;234m'
  else
    PURPLE='\033[38;5;99m'
  fi
fi

# Symbols and separator per tier. Non-ASCII always uses a straight powerline
# divider (│), no Nerd font required — it's a plain box-drawing character.
if [[ "$USE_ASCII" == "1" ]]; then
  S_BRAND='<>'
  S_BRANCH='>'
  SEP=' | '
else
  S_BRAND='◆'
  S_BRANCH='⎇'
  SEP=' \u2502 '
fi

# 10-step rainbow gradient (violet -> red), one per rendering tier.
GRAD_R=(204 68 0 0 0 0 102 238 255 255)
GRAD_G=(0 0 68 204 255 255 255 255 136 0)
GRAD_B=(255 255 255 255 170 34 0 0 0 0)
GRAD256=(165 57 27 45 49 47 118 226 214 196)

# render_bar PCT -> writes a 10-cell gradient/ASCII bar (raw escape bytes) to $bar_out
render_bar() {
  local pct=$1 cells=10 filled i bar=""
  filled=$(( (pct * cells + 99) / 100 ))
  (( filled > cells )) && filled=$cells
  (( filled < 0 )) && filled=0
  if [[ "$USE_ASCII" == "1" ]]; then
    for (( i = 0; i < cells; i++ )); do
      if (( i < filled )); then bar+='#'; else bar+='-'; fi
    done
  elif (( USE_TRUECOLOR )); then
    for (( i = 0; i < cells; i++ )); do
      if (( i < filled )); then
        bar+="\033[38;2;${GRAD_R[$i]};${GRAD_G[$i]};${GRAD_B[$i]}m█"
      else
        bar+='\033[38;2;60;60;60m░'
      fi
    done
    bar+="$RESET"
  else
    for (( i = 0; i < cells; i++ )); do
      if (( i < filled )); then
        bar+="\033[38;5;${GRAD256[$i]}m█"
      else
        bar+='\033[38;5;240m░'
      fi
    done
    bar+="$RESET"
  fi
  bar_out=$(printf '%b' "$bar")
}

# Git branch (skip optional locks so this never blocks/writes to the repo)
branch=""
if git --no-optional-locks -C "$raw_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git --no-optional-locks -C "$raw_dir" branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git --no-optional-locks -C "$raw_dir" rev-parse --short HEAD 2>/dev/null)
fi

if [ -n "$remaining" ]; then
  # Report context *used*, so it climbs as the window fills — same direction as
  # the 5h bar. The payload gives remaining, so invert it.
  rem_int=${remaining%.*}
  used_int=$(( 100 - rem_int ))
  if [ "$used_int" -ge 90 ]; then
    ctx_color=$RED
  elif [ "$used_int" -ge 70 ]; then
    ctx_color=$YELLOW
  else
    ctx_color=$GREEN
  fi
  ctx_part=$(printf '%bctx %d%%%b' "$ctx_color" "$used_int" "$RESET")
else
  ctx_part=""
fi

if [ -n "$five_hour" ]; then
  five_int=${five_hour%.*}
  if [ "$five_int" -ge 90 ]; then
    five_color=$RED
  elif [ "$five_int" -ge 70 ]; then
    five_color=$YELLOW
  else
    five_color=$GREEN
  fi
  render_bar "$five_int"
  five_part=$(printf '%s %b%d%%%b' "$bar_out" "$five_color" "$five_int" "$RESET")

  # Time left until the 5h window resets. Guard the arithmetic: resets_at is an
  # epoch integer today, but a non-numeric value would otherwise make bash emit
  # an error straight into the statusline. Skip the countdown instead.
  five_epoch=${five_reset%.*}
  if [[ $five_epoch =~ ^[0-9]+$ ]]; then
    secs=$(( five_epoch - $(date +%s) ))
    if [ "$secs" -gt 0 ]; then
      mins=$(( (secs + 59) / 60 ))   # round up, so it never reads 0m while time remains
      if [ "$mins" -ge 60 ]; then
        left_fmt=$(printf '%dh%02dm' $((mins / 60)) $((mins % 60)))
      else
        left_fmt=$(printf '%dm' "$mins")
      fi
      five_part="${five_part} ${DIM}${left_fmt}${RESET}"
    fi
  fi
else
  five_part=""
fi

# Line 1: brand + model (matching color) · cost · ctx · 5h bar
printf "${PURPLE}%b %s${RESET}" "$S_BRAND" "$model"
printf "%b${GOLD}%s${RESET}" "$SEP" "$cost_fmt"
if [ -n "$ctx_part" ]; then
  printf "%b%b" "$SEP" "$ctx_part"
fi
if [ -n "$five_part" ]; then
  printf "%b%b" "$SEP" "$five_part"
fi
printf '\n'

# Line 2: cwd · git branch
printf "${CYAN}%s${RESET}" "$dir"
if [ -n "$branch" ]; then
  printf "%b${MAGENTA}%b%s${RESET}" "$SEP" "$S_BRANCH" "$branch"
fi
printf '\n'
