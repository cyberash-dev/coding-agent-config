# Arc VCS (not Git)

All projects live in the Arcadia monorepo and use Arc, not Git. Key differences from Git:

- Main branch is `trunk`, not main/master
- Remote branches: `users/<login>/<name>`
- Lazy fetch is on by default — no need to `arc fetch` before checkout/pull
- `arc submit` = create branch + commit + create/update PR in one command
- SVN revisions: `r<number>` (e.g. `r6666666`)
- `.arcignore` = `.gitignore` equivalent
- Working copy is FUSE-mounted (virtualized)

## Essential commands

```
arc status / arc diff / arc diff --cached    # state & changes
arc add <files> / arc commit -m "msg"        # stage & commit
arc checkout -b <branch> / arc checkout -    # branches
arc pull / arc rebase trunk                  # update from trunk
arc push -u users/<login>/<branch>           # push to server
arc submit -m "title" --publish              # quick PR workflow
arc pr create / arc pr list / arc pr view    # PR management
arc stash push / arc stash pop               # stash
arc log --oneline -n 20 / arc blame <file>   # history
```

## Rules

- Use `arc` commands, never `git`
- Prefer `arc submit` for simple PR workflows
- Do not `arc push --force` or `arc reset --hard` without explicit user request
- Commit-message rules from `rules/commits.md` apply (no Co-Authored-By, etc.)
- Short numeric flags like `-5` are NOT supported. Always use the explicit
  long form: `arc log -n 5`, not `arc log -5`. Same for any count argument —
  pass it via the named flag (`-n`, `--limit`, etc.), never as `-<number>`.
