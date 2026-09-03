# claude-statusline

A custom statusline for [Claude Code](https://claude.com/claude-code).

```
◆ Opus 5  $1.23  ctx 38%  ████░░░░░░ 38% 2h14m left
~/projects/demo  ⎇main
```

Two lines, segments joined by powerline arrows. Line 1: brand mark + model
(same color) · session cost · context window used as a percentage · 5-hour
rate-limit usage as a gradient bar, with time until the window resets. Line
2: working directory · git branch (with a branch icon).

Both percentages read as *consumption* and climb toward their limit, colored
green, yellow from 70%, red from 90%. The payload reports context as
remaining, so the script inverts it.

## Rendering tiers

Color capability cascades through three tiers, picked once per run:

1. **True color** — a smooth 24-bit green→yellow→red gradient, per cell of
   the bar. Enabled when `COLORTERM=truecolor` or `COLORTERM=24bit` (most
   modern terminals set this automatically).
2. **256-color** — the same gradient shape approximated with `\033[38;5;Nm`
   codes. The default when true color isn't detected.
3. **ASCII** — no color codes or Unicode at all; bars render as `#`/`-`, the
   brand mark as `<>`, and the segment separator as a plain `|` instead of
   the powerline arrow. Force it with `CLAUDE_STATUSLINE_ASCII=1` for dumb
   terminals, logging, or copy-pasting the statusline as plain text.

## Configuration

Environment variables (set in `~/.zshrc` or `~/.bashrc`):

| Variable | Default | Effect |
|---|---|---|
| `CLAUDE_STATUSLINE_ASCII` | `0` | `1` forces the plain ASCII tier: no color, no gradient bars, `|` separators instead of powerline arrows |
| `COLORTERM` | unset | `truecolor` or `24bit` enables the true-color gradient tier |

The powerline arrow separator (``) needs a Nerd/powerline font — same
requirement as the gradient bar's block characters.

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
