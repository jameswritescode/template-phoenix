---
name: remove-auth
description: Use when a project derived from this template does not want the built-in authentication layer (accounts, login, passkeys) — removes it wholesale with the verified script instead of hand-deleting files.
---

# Remove the auth layer

Run the script; never delete auth files by hand (shared files carry
`auth:begin`/`auth:end` regions the script strips precisely):

```sh
bin/remove-auth.sh
mix setup
mix precommit   # heals mix.lock (prunes wax_/argon2/mox) and proves the gate
```

The script is all-or-nothing: it aborts before deleting anything if the
tree doesn't match its inventory. It removes itself, its e2e
(`bin/test-remove-auth.sh`), its CI job, and this skill when done.

If it aborts, the tree has drifted from the template's auth layout — do
NOT work around it by hand; investigate the drift first.
