---
name: tophat
description: Use when asked to tophat a change, manually verify a feature in a real browser, or confirm UI/LiveView/controller work actually renders and behaves before calling it done. Also use before claiming any user-facing change works.
---

# Tophatting

Tophatting = running the app and exercising a change in a real browser, the way a user would.

## Start your own server — never reuse one

Servers already listening (on 4000, 4001, ...) may belong to the user or other
projects. Do not probe them, read their process info, or restart them. Instead:

```sh
mise exec -- mix server --subdomain tophat-<your-task>
```

- **Always pass `--subdomain`, and make the name yours**: derive it from what
  you are tophatting (branch or feature name, e.g. `tophat-checkout-flow`).
  Never plain `localhost`, never bare `tophat`, and never a subdomain another
  agent or the user may be using — the subdomain is what isolates your cookies,
  sessions, and origin from theirs
- In a worktree, the `.env`-pinned `PORT` and `SUBDOMAIN` belong to the
  worktree's main dev server — often the user's, already running. Never take
  them for tophatting: clear the pin so the free-port scan runs instead:

  ```sh
  mise exec -- env PORT= mix server --subdomain tophat-<your-task>
  ```

- Picks the first free port in 4000-4500 automatically and prints
  `Starting server on http://tophat-<your-task>.localhost:<port>` — parse that
  URL from the output; no `lsof` surveying needed
- A busy port — pinned or otherwise — is **never yours to free**: the scan
  already avoids busy ports; never kill, restart, or stop a process you did
  not start
- `--port N` forces a specific port if you need one

Run it in the background with output captured to a log file. Poll with `curl`
until the URL returns a response before opening the browser; if it never comes
up, read the log (look for `eaddrinuse`, compile errors, crash reports).

## Tophat in Chrome

Use the browser automation tools (in Claude Code, load the `claude-in-chrome`
skill first). Open a new tab, navigate to the printed URL, then verify:

1. **The change itself** — click through the modified flow end to end,
   including an error/edge case, not just the happy path. Screenshot the result.
2. **LiveView health** — `[data-phx-main]` element has class `phx-connected`
   (websocket joined); live navigation updates without full page reloads.
3. **Console and network** — read console messages (errors only) and network
   requests; there should be no JS errors or failed requests.
4. **Server log** — no errors or crash reports in your server's log.

## Clean up — required

- Stop the server process you started; confirm its port is free again
- Close browser tabs you opened
- Leave any servers you did not start exactly as you found them
- Leave the working tree clean (your server log belongs in scratch space, not
  the repo)
