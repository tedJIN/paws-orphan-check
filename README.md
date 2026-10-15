# orphan-check

A Claude Code plugin that reports processes AI coding sessions left running after they ended:
MCP servers, `node`/`npx`/`uv` workers, Playwright and Chrome-for-Testing helpers.
It is **read-only**. It runs `ps`, groups what it finds, and prints a table. It never stops anything.

```
COUNT   MEMORY      OLDEST        COMMAND
3       134 MB      00:01         node -e setInterval(()=>{},1e9) fake-mcp-server-orphancheck

Total: 3 leftover processes in 1 groups, about 0.1 GB (RSS incl. children; upper bound).
```
(The sample above is from a test run with three deliberately orphaned processes.)

## Why not just count processes whose parent is launchd?

`ps -eo ppid= | awk '$1==1' | wc -l` returns hundreds on a healthy Mac. Browsers, Spotify and most Apple helpers
are legitimately parented to launchd, so having no parent is not evidence of being a leftover.
CPU doesn't work either: a Claude Code session waiting for your input sits at 0% CPU.

So a process is reported only when **all** of these hold:

1. Its parent is launchd/init (necessary, not sufficient).
2. No terminal session owns it: no controlling tty, no foreground process group. A live session holds its
   whole family, ancestors and descendants.
3. Its command looks like agent tooling (MCP, node/npx/uv/python workers, Playwright/devtools helpers).
4. Three or more identical command lines piled up. One copy might be doing work; a pile of identical
   unowned copies is the leftover pattern.

Apple system processes and XPC services are never reported. Memory is RSS including children, so totals
are an upper bound.

## Install

```
/plugin marketplace add tedJIN/paws-orphan-check
/plugin install orphan-check@paws-tools
```

Then ask Claude "is anything left over from old sessions?" or run `/orphan-check:orphan-check`.
You can also run the script directly: `bash scripts/orphan-check.sh` (macOS or Linux, bash + awk + ps).

## Privacy

Nothing is sent anywhere. The script makes no network calls and writes no files.

## About

Made by the author of [Paws](https://tedjin.github.io/paws/en/?utm_source=cc-plugin), a macOS menu bar app that
watches for this continuously and cleans up with the same session-aware rule. This plugin is free and
works on its own.

MIT licensed.
