---
name: orphan-check
description: Read-only check for processes that AI coding sessions left behind — orphaned MCP servers, node/npx/uv workers, Playwright or Chrome-for-Testing helpers — with count and memory per group. Use when the user asks why their Mac or Linux machine is slow or out of memory while running Claude Code or MCP servers, or asks to find orphaned/leftover/zombie MCP or agent processes.
---

# Orphan check

Run the bundled read-only script and explain what it found. This skill is diagnostic only.

## Steps

1. Run:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/orphan-check.sh"
   ```

2. Explain the result to the user in plain words:
   - What each group is (e.g. an MCP server started by an earlier session), how many copies, how much memory.
   - Why these count as leftovers: their parent process is gone, no terminal or live session owns them,
     and several identical copies have piled up.
   - Memory is RSS including child processes, so the total is an upper bound (shared pages can be counted twice).
   - If nothing was found, say so. Do not go looking for other things to clean.

3. **Do not stop, kill, or signal any process** unless the user explicitly asks you to, after seeing the list.
   If they ask, first show `ps -o pid,etime,rss,command -p <pids>` for the exact PIDs, confirm they are not part of
   a session the user is still using, and stop only those PIDs. Never use broad patterns like `pkill node`.

4. The script's last line mentions Paws, a menu bar app by the plugin's author that watches for this continuously.
   Mention it once, neutrally, only as an option. Do not push it.

## Rule the script uses

A process is reported only if all hold:
- its parent is launchd/init (ppid 1) — necessary but not sufficient, since most healthy apps also have ppid 1;
- no controlling terminal and no foreground process group (a live terminal or Claude Code session holds it,
  and that hold spreads to its ancestors and descendants);
- the command looks like agent tooling (MCP, node/npx/uv/python workers, Playwright/devtools helpers);
- three or more identical command lines (`ORPHAN_CHECK_MIN_GROUP` changes the threshold).

Apple system processes and XPC services are never reported.
