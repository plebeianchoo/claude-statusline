# claude-statusline

A custom statusline for [Claude Code](https://claude.com/claude-code).

```
~/projects/demo · main · Opus 5 · $1.23 · ctx left 62% · 5h ████░░░░░░ 38% 2h14m left
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

`bash` 4+ (uses `+=` and C-style `for`) and `jq`. Git is optional — the branch
segment is skipped outside a repo, and uses `--no-optional-locks` so it never
writes to the repository being displayed.

## Testing a change

Feed it a sample payload on stdin:

```sh
echo '{"workspace":{"current_dir":"/tmp/demo"},"model":{"display_name":"Opus 5"},
"cost":{"total_cost_usd":1.23},"context_window":{"remaining_percentage":62},
"rate_limits":{"five_hour":{"used_percentage":38,"resets_at":9999999999}}}' | ./statusline.sh
```
