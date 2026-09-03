#!/usr/bin/env bash
# Claude Code statusline: cwd · git branch · model · session cost · context left · 5h rate limit
input=$(cat)

raw_dir=$(jq -r '.workspace.current_dir // .cwd // "?"' <<<"$input")
dir=${raw_dir/#$HOME/\~}

model=$(jq -r '.model.display_name // .model.id // "?"' <<<"$input")
cost=$(jq -r '.cost.total_cost_usd // 0' <<<"$input")
cost_fmt=$(printf '$%.2f' "$cost")

remaining=$(jq -r '.context_window.remaining_percentage // empty' <<<"$input")
five_hour=$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$input")
five_reset=$(jq -r '.rate_limits.five_hour.resets_at // empty' <<<"$input")

RESET='\033[0m'
DIM='\033[2m'
CYAN='\033[36m'
BLUE='\033[34m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
GOLD='\033[38;5;220m'

# Git branch (skip optional locks so this never blocks/writes to the repo)
branch=""
if git --no-optional-locks -C "$raw_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git --no-optional-locks -C "$raw_dir" branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git --no-optional-locks -C "$raw_dir" rev-parse --short HEAD 2>/dev/null)
fi

if [ -n "$remaining" ]; then
  rem_int=${remaining%.*}
  if [ "$rem_int" -le 10 ]; then
    ctx_color=$RED
  elif [ "$rem_int" -le 30 ]; then
    ctx_color=$YELLOW
  else
    ctx_color=$GREEN
  fi
  ctx_fmt=$(printf 'ctx left %d%%' "$rem_int")
  ctx_part="${ctx_color}${ctx_fmt}${RESET}"
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
  # Bar: 10 cells, filled proportionally to usage (round up so 1% shows one cell)
  cells=10
  filled=$(( (five_int * cells + 99) / 100 ))
  [ "$filled" -gt "$cells" ] && filled=$cells
  bar=""
  for ((i = 0; i < cells; i++)); do
    if [ "$i" -lt "$filled" ]; then bar+="\u2588"; else bar+="\u2591"; fi
  done
  five_fmt=$(printf '5h %b %d%%' "$bar" "$five_int")
  five_part="${five_color}${five_fmt}${RESET}"

  # Time left until the 5h window resets
  if [ -n "$five_reset" ]; then
    secs=$(( ${five_reset%.*} - $(date +%s) ))
    if [ "$secs" -gt 0 ]; then
      mins=$(( (secs + 59) / 60 ))   # round up, so it never reads 0m while time remains
      if [ "$mins" -ge 60 ]; then
        left_fmt=$(printf '%dh%02dm left' $((mins / 60)) $((mins % 60)))
      else
        left_fmt=$(printf '%dm left' "$mins")
      fi
      five_part="${five_part} ${DIM}${left_fmt}${RESET}"
    fi
  fi
else
  five_part=""
fi

printf "${CYAN}%s${RESET}" "$dir"
if [ -n "$branch" ]; then
  printf " · ${MAGENTA}%s${RESET}" "$branch"
fi
printf " · ${BLUE}%s${RESET} · ${GOLD}%s${RESET}" "$model" "$cost_fmt"
if [ -n "$ctx_part" ]; then
  printf " · %b" "$ctx_part"
fi
if [ -n "$five_part" ]; then
  printf " · %b" "$five_part"
fi
printf '\n'
