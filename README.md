# claude-statusline

A custom statusline for [Claude Code](https://claude.com/claude-code).

```
~/projects/demo · main · Opus 5 · $1.23 · ctx 62% · ████░░░░░░ 38% 2h14m left
```

Shows, left to right: working directory · git branch · model · session cost ·
context window remaining · 5-hour rate-limit usage as a 10-cell bar, with time
until the window resets.

Context and usage are color-coded — green, yellow past 70%, red past 90% (the
context readout inverts: it warns as *remaining* drops below 30% and 10%).

## Install

```sh
git clone git@github.com:plebeianchoo/claude-statusline.git ~/dotfiles/claude-statusline
mkdir -p ~/.claude
ln -sf ~/dotfiles/claude-statusline/statusline.sh ~/.claude/statusline.sh
```

Then point `~/.claude/settings.json` at it:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

Restart Claude Code to pick it up.

## Requirements

| Tool | Why | Required? |
|---|---|---|
| `bash` 4.2+ | The bar is built with `printf '%b'` over `\uXXXX` escapes, and `\u` support in `printf` landed in bash 4.2. macOS ships bash 3.2 at `/bin/bash`, where the bar renders as the literal text `\u2588` — install a newer one (`brew install bash`). The shebang is `/usr/bin/env bash`, so it picks up whichever bash comes first on `PATH`. | **Yes** |
| `jq` | Parses the JSON status payload Claude Code writes to stdin. Every field — cwd, model, cost, context, rate limits — comes through it. | **Yes** |
| `git` | The branch segment. Uses `--no-optional-locks`, so it never writes to the repo being displayed. | No — segment is skipped if absent, or outside a work tree |
| `date` | `date +%s` for the reset countdown. Only `%s` is used — POSIX, so BSD/macOS `date` works unmodified. | **Yes**, but universally present |
| `printf`, `cat` | Output and reading stdin. Both bash builtins or coreutils. | **Yes** (always present) |

Verified against: bash 5.2.21, jq 1.7, git 2.43.0, GNU coreutils 9.4.

### Terminal

| Need | Detail |
|---|---|
| UTF-8 locale | The bar draws `█` (U+2588) and `░` (U+2591). With a non-UTF-8 `LANG` these render as mojibake. Check with `locale`; expect something ending in `.UTF-8`. |
| A font covering U+2588/U+2591 | Nearly every monospace programming font does. If the bar shows as boxes, the font is the cause, not the script. |
| 256-color ANSI | The cost segment uses `\033[38;5;220m`. In a 16-color terminal it degrades to a default color rather than breaking. |

Over SSH, the locale is the usual culprit — many clients forward `LANG` from
the *local* machine. If the bar looks wrong only over SSH, that's why.

### Install the required tools

```sh
# Debian/Ubuntu
sudo apt install jq git

# macOS
brew install jq git bash

# Fedora
sudo dnf install jq git
```

Verify everything at once:

```sh
bash --version | head -1 && jq --version && git --version && locale | grep LANG
```

## Testing a change

Feed it a sample payload on stdin:

```sh
echo '{"workspace":{"current_dir":"/tmp/demo"},"model":{"display_name":"Opus 5"},
"cost":{"total_cost_usd":1.23},"context_window":{"remaining_percentage":62},
"rate_limits":{"five_hour":{"used_percentage":38,"resets_at":9999999999}}}' | ./statusline.sh
```
