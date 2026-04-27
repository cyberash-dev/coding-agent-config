# Arcadia CI (a.yaml)

CI/CD lives in `a.yaml` files alongside project code. Full schema is too large
to inline — read these references when working with a.yaml:

- `~/.claude/yandex/refs/ci-ayaml-reference.md` —
  jobs, actions, releases, runtime
- `~/.claude/yandex/refs/ci-tasks-and-filters.md` —
  filters, tasks, expressions, cleanup

## Mental model
- **Flow** = DAG of jobs. **Job** = single task execution
- **Action** = flow triggered by event (`pr` | `commit` | `schedule`)
- **Release** = multi-stage flow (stages run sequentially)
- Jobs run in **Sandbox** (default) or **Tasklet v2** runtime
- Tasks come from registry at `/ci/registry/`

## Filter logic (commonly miswritten)
- Fields within one filter: **AND**
- Multiple filters in array: **OR**
- Multiple paths in one field: **OR**
- Path types: `sub-paths`, `abs-paths`, `graph-sub-paths`, `graph-abs-paths`,
  `ignore-*`, `deny-*`
- Metadata filters: `st-queues`, `authors`, `messages`, `labels`,
  `feature-branches` (with `not-*` variants)

## CLI

```
ya tool ci validate [path/to/a.yaml]     # validate config
ya tool ci generate [path/to/a.yaml]     # render full config (resolve includes)
ya tool ci delegate [path] <branch>      # delegate vault access
```
