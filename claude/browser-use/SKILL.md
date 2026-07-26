---
name: browser-use
description: Set up and drive a real browser (Playwright MCP) to perform a given action on the web — navigate, log in, fill forms, click through flows, search/filter listings, extract data, take screenshots. The action to perform is an input parameter; this skill covers getting the browser working and how to reliably drive it, not any one specific task. Use when asked to open/use/automate a website or browser, fix a broken playwright MCP connection, or perform a web task that requires clicking, typing, or reading a live page.
---

Drives a real, headed Chromium instance via the **Playwright MCP server**
(`@playwright/mcp`), exposed to Claude Code as the `mcp__playwright__*`
tools (`browser_navigate`, `browser_snapshot`, `browser_click`,
`browser_type`, `browser_find`, `browser_tabs`, `browser_evaluate`,
`browser_take_screenshot`, …). There is no separate driver script — once
the MCP server is connected, those tools **are** the harness. `setup.sh` in
this directory is what gets the server into a working state; it's the part
that actually needed fighting with.

**The action to perform is supplied by whoever invokes this skill** — a
login flow, a form submission, a multi-site search, a scrape, whatever. This
document covers the reusable part: getting a browser you can drive at all,
and the patterns that make driving it reliable once you have one. It does
not encode any particular task.

**The server is registered once, globally, at user scope** — available in
every project without per-project config or restarts. **Browser context is
still per-project**, though: the server is launched with a *relative*
`--user-data-dir` (`.claude/browser-profile`), and the playwright-mcp
subprocess inherits its cwd from whichever project directory the Claude Code
session was started in. So one global registration still resolves to an
isolated, persistent profile directory per project — logins/cookies in one
project don't leak into or get wiped by another, and there's no restart
needed when moving to a new project.

## Prerequisites

None at the OS package level — everything installs into the user's home
directory (nvm, Node, the user-scoped MCP registration) and the current
project directory (browser profile only). No `sudo` needed. Verified inside
a WSL2/WSLg container.

## Setup

Run from the project root that should get its own browser profile:

```bash
cd /path/to/your/project
bash ~/.claude/skills/browser-use/setup.sh
```

Idempotent — safe to re-run any time the MCP connection is broken. In order:

1. Installs `nvm` (if missing) and Node 20 via it. **The system `node` is
   commonly older than 20, and `@playwright/mcp` hard-refuses to start
   below Node 20** — the #1 cause of a dead MCP connection.
2. Installs `@playwright/mcp` globally under that Node 20.
3. Runs `playwright-mcp install-browser chrome-for-testing` — downloads the
   actual browser binary. The MCP server does **not** use Playwright's
   normal bundled Chromium; it launches under a `chrome-for-testing`
   channel that needs its own explicit install.
4. Creates `<project>/.claude/browser-profile/` (persistent — logins survive
   across sessions) unless `BROWSER_PROFILE_REL` is set to a different
   relative path.
5. Registers the `playwright` MCP server at **user scope** (`claude mcp add
   ... -s user`) if not already registered with a relative profile path —
   this touches `~/.claude.json`, not any project's `.mcp.json`. Points
   `command` directly at the Node 20 binary and the `playwright-mcp` script
   path — **not** `npx` — with `--user-data-dir=.claude/browser-profile`
   (relative, so it resolves per-project at launch time).

Override the target project or the relative profile path:

```bash
PROJECT_DIR=/path/to/project BROWSER_PROFILE_REL=.claude/custom-profile \
  bash ~/.claude/skills/browser-use/setup.sh
```

The **first time ever** the server is registered, **restart Claude Code**
(or otherwise force it to reconnect MCP servers) so the `mcp__playwright__*`
tools load. Verify with:

```bash
claude mcp list
```

Expected: `playwright: ... ✔ Connected` (scope: user config). After that
first restart, running `setup.sh` in a *different* project needs no further
restart — the server is already registered; only its per-project profile
directory gets created fresh.

## Run (agent path)

Once connected, drive the browser directly — this loop is the harness:

```
mcp__playwright__browser_navigate        { url }
mcp__playwright__browser_snapshot        ()                    # accessibility tree + element refs
mcp__playwright__browser_click           { element, target }   # target = a ref from the latest snapshot
mcp__playwright__browser_type            { element, target, text, submit? }
mcp__playwright__browser_find            { text | regex }      # full-text search over the snapshot
mcp__playwright__browser_tabs            { action: list|new|select|close, index?, url? }
mcp__playwright__browser_evaluate        { function }          # arbitrary JS in page context
mcp__playwright__browser_take_screenshot ()                    # → .playwright-mcp/*.png
```

General procedure for any given action:

1. `browser_navigate` to the starting URL.
2. `browser_snapshot` to get element refs and see what's actually there.
3. `browser_click` / `browser_type` using those refs to make progress
   toward the action.
4. **Re-snapshot after every mutating action** before clicking again — refs
   go stale the instant the DOM changes (see Gotchas).
5. If the action needs data extracted or verified, `browser_find` or read
   the snapshot text rather than guessing from memory.
6. If the action needs proof (screenshot, confirmation a form went through),
   take it before declaring done.

The browser runs **headed** (no `--headless` flag), so a real window exists
on the desktop (via WSLg, X11, or the host's own display) — this is
intentional: it lets a human watch progress, and some sites behave
differently or degrade under headless detection.

Screenshots and per-navigation console/snapshot logs land in
`.playwright-mcp/` under whichever project's tools are active.

## Run (human path)

N/A — there's no separate human UI. The browser window itself opens on the
desktop as soon as a tool call navigates somewhere; a human can watch or
even interact with it directly while the agent drives it.

## Gotchas

- **`npx playwright-mcp` silently re-execs under the wrong Node**, even
  after installing Node 20 via nvm — it prints "You are running Node.js
  18.x" and refuses to start. `npx`'s shebang re-resolves `node` via `PATH`
  at spawn time, and the MCP server's environment doesn't have nvm's bin
  dir on `PATH`. **Fix**: bypass `npx` — install `@playwright/mcp` globally
  and point the registered `command` straight at the Node 20 binary, with
  the `playwright-mcp` script path as the first arg (`setup.sh` does this).
- **Default browser channel isn't Playwright's bundled Chromium.** Even
  with `--browser=chromium` set, the server looks for a "chrome-for-testing"
  binary and fails with `Browser "chrome-for-testing" is not installed`
  until `playwright-mcp install-browser chrome-for-testing` is run
  explicitly — a plain `npx playwright install chromium` installs a
  different, non-matching build and does not fix this.
- **A newly-registered MCP server requires a full Claude Code restart**
  to take effect — registering or editing it mid-session does not
  hot-reload the connection or its tool set. This only bites once, the
  first time `playwright` is registered on a machine; since it's
  user-scoped afterward, later projects don't re-trigger it.
- **A relative `--user-data-dir` depends on the subprocess's cwd, not on
  which project "feels current."** Claude Code launches the MCP subprocess
  with cwd set to the session's project root, so the relative path resolves
  correctly per-project automatically — but if that assumption ever breaks
  (e.g. a wrapper that launches Claude Code from a fixed directory), profiles
  would silently collapse into one shared directory. Sanity-check with
  `readlink -f /proc/<pid>/cwd` on the running `playwright-mcp` process
  (`pgrep -f 'playwright-mcp --browser=chromium'`) if profiles seem to be
  bleeding across projects.
- **Element refs from `browser_snapshot` go stale on every DOM mutation**,
  including a re-render triggered by your own click. Clicking one checkbox
  then reusing a ref from the *pre-click* snapshot for the next one fails
  with `Ref eXXX not found in the current page snapshot`. Always re-snapshot
  between sequential interactions on a dynamic page.
- **"Frame was detached" / "Execution context was destroyed" errors on
  ad-heavy pages are often false negatives**, not real failures — ad
  iframes reload constantly and can make `browser_navigate` or even
  `browser_snapshot` report an error while the underlying action actually
  succeeded. Retry with `browser_snapshot` before assuming failure. If a
  tab gets stuck in a genuine reload loop (every call on it errors
  repeatedly), open a **new tab** to the same URL via `browser_tabs
  {action:"new", url}` and close the stuck one rather than continuing to
  fight it. `browser_evaluate` running `window.location.href = ...` also
  works as a navigation escape hatch when `browser_navigate` itself is
  wedged. Ad popups can also spawn extra unprompted tabs — check
  `browser_tabs {action:"list"}` if the current tab isn't what you expect.
- **A site's own in-page search/filter is not a reliable substring match.**
  A description-keyword filter on one site missed a listing that *did*
  contain the exact search term, apparently due to stemming on the site's
  end. Don't trust a third-party site's own search as a correctness
  guarantee when the action depends on it — verify by reading the fully
  rendered page (`browser_find`) instead of trusting the site's result count.
- **Clicking by remembered position/label is risky on multi-purpose UIs.**
  A click aimed at one button can land on a different one that happens to
  render at a similar position in a later snapshot (e.g. a "Filters"
  toggle vs. a "Save search" button). Always click a ref obtained from a
  snapshot taken *immediately before* that click, never one reused from
  several steps earlier.

## Troubleshooting

- **`claude mcp list` shows `playwright: ... ✘ Failed to connect`, error
  text `"Playwright requires Node.js 20 or higher"`**: the registered command
  is resolving to system Node. Re-run `setup.sh` and confirm `claude mcp get
  playwright` shows `command` as an absolute path to a Node 20 binary (e.g.
  `~/.nvm/versions/node/v20.x.x/bin/node`), not `node` or `npx`.
- **Tool call errors with `Browser "chrome-for-testing" is not installed`**:
  run `<node20> <node20-dir>/playwright-mcp install-browser
  chrome-for-testing` (also handled by `setup.sh` step 3).
- **`mcp__playwright__*` tools aren't offered/callable at all**: either the
  server was just registered/re-registered for the first time this machine
  (restart Claude Code once), or a leftover project-local `.mcp.json` from
  before this skill switched to user-scope registration is shadowing/
  duplicating it — check for and remove a stray `<project>/.mcp.json`.
- **Browser profiles seem to be shared across projects instead of isolated**:
  confirm the registered `--user-data-dir` is still a relative path
  (`claude mcp get playwright`) and check the running subprocess's actual
  cwd with `readlink -f /proc/<pid>/cwd` — see the Gotchas entry above.
- **A `browser_click`/`browser_type` call fails with `Ref eXXX not found in
  the current page snapshot`**: the page re-rendered since the last
  snapshot. Call `browser_snapshot` again and use the fresh ref.
- **Same tab keeps failing every tool call with `Frame was detached` /
  `Execution context was destroyed`**: open a new tab to the same URL
  (`browser_tabs {action:"new", url}`), close the broken one
  (`browser_tabs {action:"close", index}`), continue there.
