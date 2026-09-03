#!/usr/bin/env bash
# Claude Code statusline: brand · cwd · git branch · model · session cost · context left · 5h rate limit
#
# Env vars:
#   CLAUDE_STATUSLINE_ASCII=1     force plain ASCII (no color, no unicode bars)
#   CLAUDE_STATUSLINE_POWERLINE=1 use a powerline arrow () as the segment separator
#   COLORTERM=truecolor|24bit     enables the 24-bit gradient bars (set by most modern terminals)
#
# Rendering cascades three tiers: truecolor gradient -> 256-color gradient -> ASCII,
# picked once at the top and used for every colored segment below.
set -uo pipefail

USE_ASCII="${CLAUDE_STATUSLINE_ASCII:-0}"
USE_POWERLINE="${CLAUDE_STATUSLINE_POWERLINE:-0}"
USE_TRUECOLOR=0
if [[ "${COLORTERM:-}" == "truecolor" || "${COLORTERM:-}" == "24bit" ]]; then
  USE_TRUECOLOR=1
fi

input=$(cat)

raw_dir=$(jq -r '.workspace.current_dir // .cwd // "?"' <<<"$input")
dir=${raw_dir/#$HOME/\~}

model=$(jq -r '.model.display_name // .model.id // "?"' <<<"$input")
cost=$(jq -r '.cost.total_cost_usd // 0' <<<"$input")
cost_fmt=$(printf '$%.2f' "$cost")

remaining=$(jq -r '.context_window.remaining_percentage // empty' <<<"$input")
five_hour=$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input")
five_reset=$(jq -r '.rate_limits.five_hour.resets_at // empty' <<<"$input")

if [[ "$USE_ASCII" == "1" ]]; then
  RESET='' DIM='' CYAN='' BLUE='' GREEN='' YELLOW='' RED='' MAGENTA='' GOLD='' PURPLE=''
else
  RESET='\033[0m'
  DIM='\033[2m'
  CYAN='\033[36m'
  BLUE='\033[34m'
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

# Symbols and separator per tier.
if [[ "$USE_ASCII" == "1" ]]; then
  S_BRAND='<>'
  S_BRANCH='>'
  SEP=' | '
elif [[ "$USE_POWERLINE" == "1" ]]; then
  S_BRAND='◆'
  S_BRANCH='⎇'
  SEP='  '
else
  S_BRAND='◆'
  S_BRANCH='⎇'
  SEP=' · '
fi

# 10-step green -> yellow -> red gradients, one per rendering tier.
GRAD_R=(46 116 186 241 239 236 233 231 211 192)
GRAD_G=(204 195 186 196 161 126 101 76 66 57)
GRAD_B=(113 89 64 15 24 34 44 60 50 43)
GRAD256=(46 82 118 154 190 226 214 208 202 196)

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
  render_bar "$used_int"
  ctx_part=$(printf '%s %b%d%%%b' "$bar_out" "$ctx_color" "$used_int" "$RESET")
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

printf "${PURPLE}%b${RESET} " "$S_BRAND"
printf "${CYAN}%s${RESET}" "$dir"
if [ -n "$branch" ]; then
  printf "%b${MAGENTA}%b%s${RESET}" "$SEP" "$S_BRANCH" "$branch"
fi
printf "%b${BLUE}%s${RESET}%b${GOLD}%s${RESET}" "$SEP" "$model" "$SEP" "$cost_fmt"
if [ -n "$ctx_part" ]; then
  printf "%b%b" "$SEP" "$ctx_part"
fi
if [ -n "$five_part" ]; then
  printf "%b%b" "$SEP" "$five_part"
fi
printf '\n'
