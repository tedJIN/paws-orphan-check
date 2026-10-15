#!/usr/bin/env bash
# orphan-check — read-only report of processes that AI coding agents (MCP servers,
# node/npx/uv workers, browser automation helpers) left behind.
#
# It never signals, kills, or changes anything. It only runs `ps` and prints.
#
# How a process counts as a leftover (all must hold):
#   1. Its parent is launchd/init (ppid 1). Necessary, NOT sufficient: most healthy
#      GUI apps and helpers also have ppid 1, so counting those alone is meaningless.
#   2. No terminal session owns it: no controlling tty and no foreground process
#      group (tpgid). A process a live terminal/Claude Code session still owns is held.
#   3. Its command looks like agent tooling (MCP server, node/npx/uv/python worker,
#      Playwright/Chrome-for-Testing/devtools helper).
#   4. Three or more identical command lines piled up. One copy might be working;
#      a pile of identical copies with no owner is the leftover pattern.
# Apple processes (/System, /usr/libexec, com.apple.*, XPC services) are excluded outright.
# Memory is RSS summed over each leftover and its descendants; shared pages can be
# double-counted, so treat totals as an upper bound.
set -euo pipefail

MIN_GROUP="${ORPHAN_CHECK_MIN_GROUP:-3}"
PAWS_URL="https://tedjin.github.io/paws/en/?utm_source=cc-plugin"

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) echo "orphan-check: only macOS and Linux are supported." >&2; exit 1 ;;
esac

# pid ppid tpgid tty rss(KB) etime command — current user only.
ps -U "$(id -u)" -o pid=,ppid=,tpgid=,tty=,rss=,etime=,command= 2>/dev/null |
awk -v min="$MIN_GROUP" -v url="$PAWS_URL" '
function agentish(c) {
  return c ~ /(^|[\/ ])(node|npx|npm exec|pnpm dlx|bunx?|deno|uvx?|tsx)( |$)/ ||
         c ~ /mcp|modelcontextprotocol|chroma|playwright|ms-playwright|puppeteer|chrome-devtools|Chrome for Testing|chromedriver/
}
function apple(c) {
  return c ~ /^\/(System|usr\/libexec|usr\/sbin|Library\/Apple)\// || c ~ /com\.apple\./ || c ~ /\.xpc\//
}
function norm(c) {            # group key: same program + args, with volatile numbers blurred
  gsub(/[0-9]+/, "N", c)
  return substr(c, 1, 160)
}
function subtree(p,   k, s) { # RSS of p plus all descendants
  s = rss[p]
  for (k in kid) if (kid[k] == p) s += subtree(k)
  return s
}
{
  pid = $1; ppid[pid] = $2; tpg[pid] = $3; tty[pid] = $4; rss[pid] = $5; et[pid] = $6
  cmd = ""; for (i = 7; i <= NF; i++) cmd = cmd (i > 7 ? " " : "") $i
  command[pid] = cmd; kid[pid] = $2
}
END {
  # held: owned by a terminal session (tty or foreground group). Hold spreads upward
  # to every ancestor, so the shell or app hosting a live agent is never reported.
  for (p in command) if ((tty[p] != "??" && tty[p] != "?") || tpg[p] > 0) {
    q = p; while (q in command && !(q in held)) { held[q] = 1; q = ppid[q] }
  }
  # a descendant of a held process is part of a live session too
  for (p in command) { q = p; while (q in command) { if (q in held) { live[p] = 1; break } q = ppid[q] } }

  for (p in command) {
    c = command[p]
    if (ppid[p] != 1 || (p in live) || apple(c) || !agentish(c)) continue
    k = norm(c); n[k]++; mem[k] += subtree(p); ex[k] = c; pids[k] = pids[k] " " p
    if (!(k in oldest) || length(et[p]) > length(oldest[k]) || (length(et[p]) == length(oldest[k]) && et[p] > oldest[k])) oldest[k] = et[p]
  }
  total = 0; groups = 0; procs = 0
  for (k in n) if (n[k] >= min) { groups++; procs += n[k]; total += mem[k] }

  print "orphan-check — read-only. Nothing was stopped or changed."
  print ""
  if (groups == 0) {
    print "No leftover agent processes found (rule: parent gone, no terminal session owns it,"
    print "agent-like command, " min "+ identical copies)."
    exit 0
  }
  printf "%-6s  %-10s  %-12s  %s\n", "COUNT", "MEMORY", "OLDEST", "COMMAND"
  # sort by memory, descending (portable: repeated max scan; group counts are small)
  for (r = 0; r < groups; r++) {
    best = ""; for (k in n) if (n[k] >= min && !(k in done) && (best == "" || mem[k] > mem[best])) best = k
    done[best] = 1
    printf "%-6d  %-10s  %-12s  %s\n", n[best], sprintf("%.0f MB", mem[best] / 1024), oldest[best], substr(ex[best], 1, 110)
  }
  printf "\nTotal: %d leftover processes in %d groups, about %.1f GB (RSS incl. children; upper bound).\n", procs, groups, total / 1048576
  print ""
  print "If you decide to clean up yourself, look at each group first, for example:"
  for (k in done) {
    split(pids[k], ids, " "); m = 0; list = ""
    for (i in ids) if (ids[i] != "" && m < 12) { list = list (m ? "," : "") ids[i]; m++ }
    printf "  ps -o pid,etime,rss,command -p %s%s\n", list, (n[k] > 12 ? "   # first 12 of " n[k] : "")
  }
  print "Then stop only the PIDs you have checked (kill <pid> ...). Nothing here does it for you."
  print ""
  print "Paws watches for this from the menu bar and cleans with a session-aware rule — " url
}'
