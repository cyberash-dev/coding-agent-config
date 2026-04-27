# Arcadia CI: Filters, Runtime, Tasks & Expressions

Companion to ci-ayaml-reference.md. Read when working with filters, runtime config, task registry, or expressions.

## Filters

Filters determine which commits/PRs trigger an action or release.

### Path filters

| Field | Scope | Description |
|-------|-------|-------------|
| `sub-paths` | relative to a.yaml dir | Glob patterns for changed files |
| `abs-paths` | from Arcadia root | Absolute path globs |
| `graph-sub-paths` | build deps, relative | Changes in build graph dependencies |
| `graph-abs-paths` | build deps, absolute | Changes in build graph dependencies |
| `ignore-sub-paths` | relative exclusion | Exclude matching paths |
| `ignore-abs-paths` | absolute exclusion | Exclude matching paths |
| `deny-sub-paths` | relative blocklist | Block PR if paths match |
| `deny-abs-paths` | absolute blocklist | Block PR if paths match |

`graph-discovery-mode`: `default` | `opensource` | `cached`

### Metadata filters

| Field | Description |
|-------|-------------|
| `st-queues` / `not-st-queues` | Tracker queue filter |
| `author-services` / `not-author-services` | Author's ABC service |
| `authors` / `not-authors` | Author login filter |
| `messages` / `not-messages` | Commit message regex |
| `feature-branches` / `not-feature-branches` | Branch name filter |
| `labels` / `not-labels` | PR label filter |

### Filter logic

- **Fields within a single filter**: AND (all must match)
- **Multiple filters in array**: OR (any filter can match)
- **Multiple paths within a field**: OR (any path can match)

### Example

```yaml
filters:
  # Filter 1 OR Filter 2
  - sub-paths: ['src/**', 'lib/**']           # any of these paths
    ignore-sub-paths: ['src/test/**']          # AND not test paths
    st-queues: ['MYQUEUE']                     # AND in this queue
  - abs-paths: ['common/shared/**']            # OR changes in shared
```

## Cleanup

Cleanup jobs run on specific lifecycle events.

### Action cleanup

```yaml
actions:
  my-action:
    cleanup:
      conditions:
        - reasons: [new-diff-set]       # trigger types (see below)
          cleanup: true                  # run cleanup-jobs (default: true)
          interrupt: false               # stop main flow (default: false)
      delay: 5m                          # wait before running cleanup
      on-status:                         # only trigger on these flow statuses
        - SUCCESS
        - FAILURE
        - RUNNING_WITH_ERRORS
        - WAITING_FOR_MANUAL_TRIGGER
        - WAITING_FOR_SCHEDULE
```

**Cleanup reasons (actions)**:
- `new-diff-set` — new PR iteration pushed
- `pr-merged` — PR merged (last iteration only)
- `pr-discarded` — PR closed/discarded (last iteration only)
- `finish` — flow completed (requires `delay` or `on-status`)
- `cancel` — flow cancelled (requires `delay`)
- `diff-set-revisited` — PR updated but this flow wasn't triggered (useful for cross-flow cleanup)

**Cleanup reasons (releases)**: `finish`, `cancel` (default: `cancel`)

### Cleanup jobs in flow

```yaml
flows:
  my-flow:
    jobs:
      main-job:
        task: my/task
    cleanup-jobs:
      cleanup:
        task: my/cleanup-task
        # same schema as regular jobs
```

## Task registry

Location: `/ci/registry/` in Arcadia monorepo.

### Structure
```
ci/registry/
  common/          # shared tasks (ya_build, ya_test, ya_package, deploy, etc.)
  demo/            # demo/example tasks
  projects/<name>/ # project-specific tasks
  junk/            # experimental tasks
```

### Common tasks

| Task | Purpose |
|------|---------|
| `common/arcadia/ya_build` | Build with ya make |
| `common/arcadia/ya_test` | Run tests with ya make -t |
| `common/arcadia/ya_package` | Build packages |
| `common/deploy/nanny` | Deploy via Nanny |
| `common/docker/build_image` | Build Docker image |
| `demo/greeting` | Demo task for testing |

### Task definition (in registry)

```yaml
name: MY_TASK
descriptions: ["Task description"]
maintainers: [login1]
required-parameters: [param1]
parameters:
  param1:
    description: "Parameter description"
requirements:
  cpu_count: 4
  ram_mb: 8192
```

## Expressions

### Syntax

`${expression}` — uses JMESPath with CI-specific extensions.

### Where to use

- `input` and `context-input` fields in jobs
- Task registry definitions
- `multiply.title` and `multiply.input`
- `if` conditions
- Sandbox resource queries (`tasks_resource`)
- Semaphore names

### Context variables

Available variables depend on the flow context:
- `context.flow_triggered_by` — who triggered the flow
- `context.target_revision` — target commit hash
- `context.branch` — branch name
- `context.pr_id` — PR number (if triggered by PR)
- `tasks.<job-id>.result` — output from upstream job
- Flow-vars values set via `flow-vars` or `flow-vars-ui`

### Testing

Expressions can be tested in the CI web UI on the JMESPath test tab.

## Runtime details

### Sandbox runtime (per-job or global)

```yaml
runtime:
  sandbox:
    owner: GROUP_NAME           # Sandbox quota group
    kill-timeout: 2h            # duration
    container_resource: N       # LXC container resource ID
    porto_layers: [N]           # Porto layer resource IDs
    headers:                    # custom headers
      key: value
    tags: [string]              # Sandbox tags
    hints:                      # execution hints
      key: value
    notifications:              # Sandbox-level notifications
      - recipients: [login]
        transport: telegram     # enum: telegram|email|q|juggler
        statuses: [FAILURE]
    priority:
      class: SERVICE            # enum: USER|SERVICE|BACKGROUND
      subclass: NORMAL          # enum: LOW|NORMAL|HIGH
```

### Tasklet v2 runtime

```yaml
runtime:
  tasklet:
    account_name: string        # execution account
    headers: {}
    tags: [string]
    requirements:
      container:
        cpu_limit: 4            # CPU cores
        ram_limit: 8GB          # RAM
        workdir:
          type: ssd             # enum: hdd|ssd|ram
          space: 50GB           # size
        network:
          name: string          # network name
        rootfs: {}              # root filesystem config
        tmpfs: {}               # tmpfs config
      execution_timeout: 1h     # duration
      scheduling:
        priority: N             # integer
      sandbox:                  # Sandbox-specific for Tasklet
        os_family: linux        # enum: linux|macos
        cpu_arch: x86           # enum: x86|arm
      semaphore:
        acquires:
          - name: SEM_NAME
            count: 1
      sidecars:                 # sidecar services
        arc: {}                 # Arc VCS access
        secrets: {}             # Vault secrets access
        ci_results_collector: {} # Results collection
```

### Result reuse

```yaml
runtime:
  reuse:
    enabled: true
    matching:                   # criteria for matching (default: all three)
      - commit                  # same commit hash
      - version                 # same task version
      - job-launch-number       # same launch count
    running: false              # reuse results from still-running jobs
    resource-types: []          # which resource types to reuse
    cancel-policy: continue-other  # enum: continue-other|cancel-all
    excluded-fields: []         # input fields to ignore when matching
```

## Autocheck configuration

```yaml
ci:
  autocheck:
    large-sandbox-owner: GROUP_NAME    # separate Sandbox group for large tests
    large-autostart:                   # auto-run large tests
      - target: path/to/test/*         # glob pattern
        toolchains: [gcc, clang]       # optional toolchain filter
```

Large tests: configured via `SIZE(LARGE)` macro in ya.make. Auto-run in post-commit with binary search. Manual run in PR via button.

## CLI tools

```bash
ya tool ci validate [path/to/a.yaml]       # validate config syntax and semantics
ya tool ci generate [path/to/a.yaml]       # render full config (resolve includes/extends)
ya tool ci render [path/to/a.yaml]         # alias for generate
ya tool ci delegate [path/to/a.yaml] <branch>  # delegate vault secret access to branch
ya tool ci layout (default|graphviz) <flow-id>  # change flow diagram layout in UI
```

Requirements: macOS or Linux, inside Arcadia repo (r13645534+), internal network access. New files must be `arc add`'ed first.
