---
name: browser-use
description: Set up and drive a real browser (Playwright MCP) to perform a given action on the web — navigate, log in, fill forms, click through flows, search/filter listings, extract data, take screenshots. The action to perform is an input parameter; this skill covers getting the browser working and how to reliably drive it, not any one specific task. Use when asked to open/use/automate a website or browser, fix a broken playwright MCP connection, or perform a web task that requires clicking, typing, or reading a live page.
---

Drives a real, headed Chromium instance via the **Playwright MCP server**
(`@playwright/mcp`), exposed to Claude Code and Codex as Playwright MCP
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

**The server is registered globally for each client**, with separate persistent
profiles: `.claude/browser-profile` for Claude Code and `.codex/browser-profile`
for Codex. Relative paths resolve against the MCP subprocess's working directory.
Launch the client from the intended project root. Separate profiles let both
clients run concurrently; logins are independent.

## Prerequisites

Install the Claude Code and/or Codex CLI and make it available on `PATH`.
The setup installs nvm, Node and the browser into your home directory without
sudo. A working graphical desktop and Chromium's system libraries are required
for the headed browser.

## Browser visibility (user preference)

**Default to a headed browser visible on the user's desktop. Use headless mode
only when the user explicitly requests it.** This applies to both Claude Code
and Codex, including requests that simply say "open the browser".

Verify the actual browser after connecting or launching. Successful navigation
or a snapshot does not prove that a visible window opened. Checking
`navigator.userAgent` with `browser_evaluate` can detect `HeadlessChrome`;
its absence alone does not prove desktop visibility. Check the actual launch
options and desktop display when needed. Do not infer the connected server's
mode from the local registration: the tool may use a different server.

If the connected browser is headless, launch or reconnect to a local headed
Playwright instance on the user's desktop, with `headless: false` when using
the Playwright API (and no `--headless` flag for the MCP server). Keep its
connection alive so the window remains open. If a visible browser cannot be
launched, explain the blocker instead of silently falling back to headless
or claiming that a desktop window opened.

If the persistent profile is locked, use a separate temporary profile for a
simple browser-opening request and disclose that existing logins are unavailable
there. For tasks requiring existing logins, resolve the profile conflict before
continuing. Do not terminate unrelated browser sessions or delete live locks.

## Setup

Run the setup script alongside this skill from the intended project root.
The repository installs identical copies at these locations:

```bash
# Either copy registers every installed client (Claude Code and/or Codex).
bash ~/.claude/skills/browser-use/setup.sh
# Or, from Codex's user skill directory:
bash ~/.agents/skills/browser-use/setup.sh
```

Safe to re-run. The script:

1. Installs nvm (if missing) and Node 20, avoiding older system Node versions.
2. Installs `@playwright/mcp` under that Node and downloads Chrome for Testing.
3. Creates each client's profile directory in the current project.
4. Registers `playwright` using `claude mcp add -s user` and/or `codex mcp add`.
   Claude writes user configuration to `~/.claude.json`; Codex writes to
   `$CODEX_HOME/config.toml` (default `~/.codex/config.toml`). Both invoke the
   Node binary and MCP script by absolute path, bypassing `npx`.

Select a client with `BROWSER_CLIENT=claude` or `BROWSER_CLIENT=codex`.
The default `auto` registers all installed clients; `both` requires both CLIs.
To override the project used for initial directory creation or the profile:

```bash
BROWSER_CLIENT=codex PROJECT_DIR=/path/to/project \
  BROWSER_PROFILE_REL=.codex/custom-profile \
  bash ~/.agents/skills/browser-use/setup.sh
```

`PROJECT_DIR` only controls initial directory creation, not the registered
server's working directory. `BROWSER_PROFILE_REL` overrides the profile for all
selected clients; select one client when customizing to avoid sharing a locked
profile. Keep browser profiles and `.playwright-mcp/` artifacts out of Git.

Restart the configured clients (or reconnect their MCP servers) after changing
registration. Verify the clients you installed:

```bash
claude mcp list
codex mcp list
codex mcp get playwright
```

Codex's list confirms configuration, not a successful browser launch. In a new
session, check `/mcp`, then navigate to a page and take a snapshot to verify the
connection end to end.

## Codex tool discovery

Tool namespaces and parameter names vary between clients and server versions.
Discover the tools exposed by the `playwright` MCP server and use their actual
schemas. The `mcp__playwright__*` names below illustrate Claude's naming; Codex
may expose a different prefix. If tools are deferred, search for Playwright
browser tools first. Do not assume a tool such as `browser_find` is available;
read the snapshot instead if it is absent.

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

The default is a **headed** browser on the user's desktop (via WSLg, X11,
or the host's own display), so the user can watch progress. Verify visibility
as described above; the connected tool may otherwise launch headless.

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
- **A newly-registered MCP server requires a client restart**
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
  (restart the affected client once), or a leftover project-local `.mcp.json` from
  before this skill switched to user-scope registration is shadowing/
  duplicating it — check for and remove a stray `<project>/.mcp.json`.
- **Browser profiles seem to be shared across projects instead of isolated**:
  confirm the registered `--user-data-dir` is still a relative path
  (`claude mcp get playwright` or `codex mcp get playwright`) and check the running subprocess's actual
  cwd with `readlink -f /proc/<pid>/cwd` — see the Gotchas entry above.
- **A `browser_click`/`browser_type` call fails with `Ref eXXX not found in
  the current page snapshot`**: the page re-rendered since the last
  snapshot. Call `browser_snapshot` again and use the fresh ref.
- **Same tab keeps failing every tool call with `Frame was detached` /
  `Execution context was destroyed`**: open a new tab to the same URL
  (`browser_tabs {action:"new", url}`), close the broken one
  (`browser_tabs {action:"close", index}`), continue there.

- **Codex has no browser tools**: check `codex mcp get playwright` and `/mcp`.
  Re-run with `BROWSER_CLIENT=codex` if registration is missing, then restart
  Codex. Inspect project `.codex/config.toml` for an overriding server entry.
- **Browser profile is already in use**: close the other session using that
  profile, or configure a distinct relative profile for one client. Do not
  delete a live browser's lock files.
