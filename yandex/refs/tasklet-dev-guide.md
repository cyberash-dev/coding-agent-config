# Tasklet v2 — Development & Operations Guide

## Quickstart Workflow

1. **Create namespace**: `ya tool tasklet namespace create <name>` or via UI
2. **Create account**: ABC → Quotas → "Create account in provider" → Provider "Tasklets"
3. **Create network** (optional): UI → https://tasklets.yandex-team.ru/network → "Create subnetwork"
4. **Generate project**:
   ```bash
   ya project create tasklet_v2_<lang>  # python | java | go | nodejs | swift
   # Prompts: name, ABC slug, OWNER group, YAV secret, Sandbox group
   # --empty flag for minimal template
   ```
5. **Register tasklet**: `ya tool tasklet tasklet create` (from dir with `t.yaml`)
6. **Build & upload**:
   ```bash
   ya make -r --target-platform default-linux-x86_64
   ya tool tasklet label create "dev-$(whoami)"
   ya tool tasklet build upload --build-schema <binary> --label "dev-$(whoami)"
   ```
7. **Run**: `ya tool tasklet run "dev-$(whoami)" sample-input.json -i json`
8. **Configure CI/CD**: create `stable` label, setup `a.yaml` with build+move-label flow

---

## SDK

### Common concepts

Every tasklet has:
- `input` — input protobuf message
- `output` — output protobuf message
- `taskletContext` — access to environment (sidecars, meta, etc.)

### Language support

| Feature | Python | Java | Go | Node.js | Swift |
|---------|--------|------|----|---------|-------|
| Secrets (gRPC) | Yes | Yes | Yes | Yes | Yes |
| Sandbox Resources | Yes | Yes | Yes | Yes | Yes |
| Artifacts | Yes | No | Yes | No | Yes |
| Arc Sidecar | Yes | Yes | Yes | Yes | Yes |
| CI Sidecar | Yes | Yes | Yes | Yes | Yes |
| Mount Sidecar | Yes | No | Yes | No | Yes |

### Error handling by language

- **Python**: raise `TaskletError` exception
- **Go**: return error from `Run` function
- **Java**: return `Result.ofError(...)`
- **Node.js**: throw `TaskletError` or use `error-interceptor` decorator
- **Swift**: throw error conforming to `TaskletError` protocol

### Testing

Use unit tests or run under `dev` label:
```bash
ya tool tasklet label create "dev-$(whoami)"
ya tool tasklet run "dev-$(whoami)" sample-input.json -i json
```

Example tests: `tasklet/tasklets/ya_project_examples/tasklet_v2_<lang>/tests/`

---

## Environment

### System guarantees

Standard containers provide:
- `/usr/bin/tar`
- `yandex-internal-root-ca` (internal certificates)
- `squashfs-tools-ng`

### Environment variables

- `TASKLET_CONTEXT` — path to serialized context proto file
- `USER`, `HOME`, `TEMP` — standard OS vars
- `PATH` — intentionally NOT set (avoid implicit dependencies)

### Context proto

`Context` message (from `tasklet/api/v2/context.proto`):
- `meta` — execution metadata
- `executor` — reference to ExecutorService gRPC
- `environment` — `EnvironmentRef` with sidecar addresses

---

## Sidecars

### Resource costs

| Sidecar | CPU | RAM | Disk |
|---------|-----|-----|------|
| Arc | 0.1 | 100MB | 50MB |
| CI | 0.1 | 100MB | 300MB |
| Sandbox Resources | 0.1 | 100MB | 70MB |
| Artifacts | 0.1 | 100MB | - |
| Secrets | 0.1 | 100MB | - |
| Xcode | 0.1 | 100MB | - |

### Arc Sidecar

Enable: `sidecars: { arc: true }`

Features:
- Mount Arcadia (`Mount` gRPC)
- Run arc commands (`Execute` gRPC)
- Get arc binary path (`GetArcBinary`)
- Get commit log (`Log` gRPC)

Usage (Go example):
```go
arcSidecar, _ := tc.ArcSidecar(ctx)
mountResp, _ := arcSidecar.Client().Mount(ctx, &arc.MountRequest{
    Commit: "trunk", Token: token,
})
// mountResp.GetMountPath() → path to Arcadia
```

### CI Sidecar

Enable: `sidecars: { ci: true }`

Modes:
- `REMOTE_COMPLETE` — from CI (full access)
- `REMOTE_BASIC` — from CLI with `secret_uid` (limited, UpdateProgress/GetCommits return stubs)
- `LOCAL` — from CLI with `@empty` (all methods return stubs)

Features:
- `UpdateTaskletProgress` — update CI badges
- `GetCommits` — commits in current flow launch
- `GetAbcServices`, `GetAbcServicesMembers` — ABC integration
- `GetDuty` — get on-call person
- `GetSchedule` / `ParseDuration` — schedule matching

### Secrets Sidecar

Enable: `sidecars: { secrets: true }`

Usage:
```python
secret_sidecar = tasklet_context.secret_sidecar()
secret = secret_sidecar.get_secret(SecretRef(id="sec-...", key="foo"))
secret.value  # secret value
```

### Sandbox Resources Sidecar

Enable: `sidecars: { sandbox_resources: true }`

Features: search, download, create Sandbox resources.

### Artifacts Sidecar

Enable: `sidecars: { artifacts: true }`

Features: CRUD artifacts. Requires OAuth token.

### Xcode Sidecar

For macOS Xcode operations. Available only in Sandbox runtime on darwin.

### Mount Sidecar

Enable: `sidecars: { mount: true }`

SquashFS/OverlayFS mount support.

---

## Secrets

### Delegation types

1. **Personal** — delegated to a user, usable in any tasklet
2. **CI (a.yaml)** — delegated to a.yaml path, usable in any flow from that a.yaml

### CLI commands

```bash
# Personal delegation
ya tool tasklet delegation create --secret_uuid sec-...

# Delegation to another user/robot
ya tool tasklet delegation create --secret_uuid sec-... --type user --source robot-login

# CI delegation
ya tool tasklet delegation create --secret_uuid sec-... --type ci --source path/to/a.yaml

# List
ya tool tasklet delegation list secret <sec-ID>
ya tool tasklet delegation list source [<login>] [--type ci]

# Revoke
ya tool tasklet delegation delete --token_uuid <tid-ID>
```

### Getting secrets from SDK

Available via `secret_sidecar` in all languages. Secret ref: `SecretRef(id, key, [version])`.

---

## CI/CD Setup

### CI tasks (from `ci/registry/common/tasklet-v2/`)

#### common/tasklet-v2/build

Builds and registers a new tasklet Build.

```yaml
jobs:
  build:
    task: common/tasklet-v2/build
    input:
      make:
        target: "path/to/tasklet"
        file_name: "binary-name"       # optional if same as dir name
        extra_args: ["-r"]             # optional
      register_build:
        t_yaml_path: "path/to/tasklet"
        label_name: "latest"           # optional, moves label on build
```

Output includes `build.meta` and `tmp_label.meta.name` (temporary label for PR testing).

#### common/tasklet-v2/move-label

Moves a label to a new Build:

```yaml
jobs:
  move-stable:
    task: common/tasklet-v2/move-label
    needs: build
    input:
      details:
        label_name: "stable"
        build_meta: "${tasks.build.build.meta}"
```

Canary release support:
```yaml
      details:
        label_name: "stable"
        build_meta: "${tasks.build.build.meta}"
        canary_release:
          percentage: 50    # 50% of executions use new build
```

#### common/tasklet-v2/run-subtasklets

Runs other tasklets from a CI job:

```yaml
jobs:
  run:
    task: common/tasklet-v2/run-subtasklets
    input:
      targets:
        - namespace: my-ns
          tasklet: my-tasklet
          label: stable
          tasklet_data: { ... }        # tasklet input
          requirements:
            account_name: "/root/generic/my-svc"
```

**Note**: Output fields serialized in `lowerCamelCase`.
Access: `${tasks.run.results[0].tasklet_output.someValue}`

#### common/swift/build_tasklet

Swift-specific build task with SPM integration.

### Testing in PR

Add a PR-triggered action:
```yaml
actions:
  test-tasklet:
    flow: test-flow
    triggers:
      - on: pr
        filters:
          - sub-paths: ['my_tasklet/**', 'a.yaml']
```

Use `tmp_label` from build output:
```yaml
# Via CI task version:
version: ${not_null(tasks.build.tmp_label.meta.name, 'stable')}

# Via run-subtasklets:
label: ${tasks.build.tmp_label.meta.name}
```

### CI runtime.tasklet section

```yaml
runtime:
  tasklet:
    account_name: /root/generic/my-service
    requirements:
      # Override container resources
      container:
        cpu_limit: 2000
        ram_limit: 2GB
      # Sidecars
      sidecars:
        arc: true
        ci: true
      # Sandbox-specific
      sandbox:
        owner: MY_GROUP
        os_family:
          mac_os:
            versions: [VENTURA, SONOMA]
      # Semaphore
      semaphore:
        semaphore_space_name: /tasklets/my-svc
        semaphore_name: my-sem
        weight: 1
      # Agent
      unit:
        unitspace_name: /my-unitspace
        unit_name: my-unit
```

Default account: `/root/generic/` + `service` from a.yaml.

---

## run_command v2

Task: `common/misc/run_command/v2`

Run arbitrary shell commands as CI jobs. Three config blocks:

### prepare block

- **sandbox.resources**: download Sandbox resources by filter/ID
- **secrets**: declare secrets to use (with `auto_decode`, `optional` options)
- **arc**: mount Arcadia (`enabled: true`, optional `revision_hash`, `extra_params`, `use_tmpfs`)
- **environment**: set env vars from values, secrets, or resource paths
- **files**: create files/symlinks to resources or secrets

### run block

- **cmd_line**: the shell script
- **interpreter**: path + args (default: `/bin/sh -e`)
- **cwd**: working directory (`arcadia: {}` | `prepare: {}` | `result: {}`)
- **logs**: redirect stdout/stderr to files

### result block

- **files**: declare output files
- **sandbox.resources**: upload Sandbox resources
- **ci.badges**: create CI badges
- **output**: populate output message
- **error**: error handling config

### Default sidecars

`sandbox_resources`, `ci`, `secrets` — always available.
Optional: `arc`, `artifacts`, `xcode`, `mount` (request via `runtime.tasklet.requirements.sidecars`).

### Key env vars (run_command)

| Variable | Description |
|----------|-------------|
| `PATH` | `/usr/local/bin:/usr/bin:/bin:...` + arc + arcadia paths |
| `HOME` | Home directory |
| `ARCADIA_PATH` | Path to mounted Arcadia (if arc enabled) |
| `ARC_TOKEN` | Arc access token |
| `ARC_BIN` | Path to arc binary |
| `YA_TOKEN` | Ya tool token |
| `TASKLET_PREPARE_PATH` | Directory with prepared files |
| `TASKLET_RESULT_PATH` | Directory for result files |
| `TASKLET_TMPFS_PATH` | tmpfs directory |
| `TASKLET_EXECUTION_ID` | Execution ID |
| `TASKLET_SANDBOX_OWNER` | Sandbox owner |
| `TASKLET_ACCOUNT` | Account name |

### Minimal example

```yaml
jobs:
  run:
    task: common/misc/run_command/v2
    input:
      config:
        run:
          cmd_line: |
            echo "Hello world"
```

### With Arcadia

```yaml
jobs:
  run:
    task: common/misc/run_command/v2
    runtime:
      tasklet:
        requirements:
          sidecars:
            arc: true
    input:
      config:
        prepare:
          arc: { enabled: true }
        run:
          cmd_line: |
            ya tool ...
```

---

## Debugging

### Remote shell

Connect to a running execution:
```bash
ya tool tasklet shell start <execution_id>
```

Requirements:
- Execution must be running in runtime
- Only execution author can connect
- Not available for PCI DSS executions (use `-c test` install instead)

### Local run

```bash
ya tool tasklet local run <binary> <input.json> --logs
  [--account <account>] [--sandbox-owner <group>]
```

Important notes:
- Works on Linux and macOS
- Custom layers ignored
- Environment may differ from runtime
- First run may be slower (cold cache)
- Not for production use
- Ensure `localhost` resolves to both `127.0.0.1` and `::1`

### File system (`~/.tasklets/`)

| Path | Contents |
|------|----------|
| `~/.tasklets/sandbox_resources` | Sandbox resource cache |
| `~/.tasklets/artifacts` | Artifact cache |
| `~/.tasklets/service_resources` | Service resources |
| `~/.tasklets/last_run` | Symlink to last workdir |
| `~/.tasklets/last_run_logs` | Symlink to last logs |

Cleanup: `rm -rf ~/.tasklets` (unmount arc first: `mount | grep fuse.arc`)

### Local sidecar behavior

| Sidecar | Local behavior |
|---------|---------------|
| Secrets | Uses CLI token directly (need Read access in YAV) |
| Sandbox Resources | Uses CLI token, creates resources under your name |
| CI | Mock mode — Get returns empty, Create has no effect |
| Arc | Works as in runtime, manages mount points |
| Xcode | All calls are stubs |

---

## Agents

### Concepts

- **Unitspace** — groups clusters of agents, has ACL
- **Unit** — cluster of agents
- **Agent** — single process executing tasklets

### Advantages

- Start time: 2-4 seconds
- Persistent cache between runs
- Custom hardware/environment

### Limitations

- User manages agent lifecycle
- No burst capacity (limited to your agents)
- One tasklet per agent at a time
- Agent restart kills running tasklet (with `is_transient=true` if `idempotent`)

### Setup with infractl

1. Create unitspace: `ya tool tasklet unitspace create /my-space --service my-abc`
2. Create unit: `ya tool tasklet unit create /my-space:my-unit`
3. Bootstrap infractl: `ya tool infractl bootstrap`
4. Configure runtime from base template:

```yaml
from: tasklet/agent/i.runtime.agent.base.yaml
patches:
  - files:
      /configs/agent.yaml: agent.yaml
    path: /configs/agent.yaml
spec:
  compute: { memory: 2G, net: 1M, vcpu: "1000" }
  replicas: { iva: 1 }
  storage: { storage_class: ssd, io_bandwidth: 15M, quota: 4G }
  network_id: _TASKLETS_SERVICE_..._NETS_
  env:
    TASKLET_TOKEN: ${sec-...:ver-...:tasklet-token}       # required
    TASKLET_LAYERS_SECRET: ${sec-...:ver-...:nirvana-token}  # optional
    TASKLET_TRACING_SECRET: ${sec-...:ver-...:tracing-token} # optional
```

### agent.yaml config

```yaml
agent:
  unitspace: /my-space
  unit: my-unit
  name: ""              # auto from pod name in YaDeploy
  type: single_porto    # single_porto | single_subprocess
cleaner:
  tasklet_cwd: { clean: true }
  service_resources: { clean: true }
  artifacts: { clean: true }
  sandbox_resources: { clean: true }
  layers_storage: { clean: true }
  home: { clean: true }
  shared: { clean: false }    # user cache directory
monitoring:
  project: monium_project
  service: monium_service
tracing:
  project: tasklets
  cluster: prod
```

### Running on agents

- CLI: `ya tool tasklet run stable input.json --unit /space:unit`
- CI:
  ```yaml
  runtime:
    tasklet:
      requirements:
        unit:
          unitspace_name: /space
          unit_name: unit
  ```

### Testing agent locally

```bash
ya tool tasklet agent run --unit /space:unit --agent-type single_subprocess
ya tool tasklet run stable input.json --unit /space:unit --sandbox-owner GROUP
```

---

## Advanced Features

### Interruptions

Enable graceful shutdown:
```yaml
spec:
  execution_timeout: 3600
  interruption_timeout: 60   # time for cleanup
```

Execution states: `Prepare` → `Active` → `Timeout`/`Abort` → `Finish`

Monitor via `GetExecutionState` gRPC stream (from ExecutorService).

SDK support: Go, Python, Node.js, Java, Swift.

### Semaphores

Limit concurrent access to external resources.

```bash
# Create
ya tool tasklet semaphore semaphore-space create /tasklets/my-svc --service my-svc
ya tool tasklet semaphore semaphore create /tasklets/my-svc:deploy-lock --capacity 1

# Use in CLI
# requirements.json:
{ "semaphore": { "semaphore_space_name": "/tasklets/my-svc", "semaphore_name": "deploy-lock", "weight": 1 } }

# Use in CI
runtime:
  tasklet:
    requirements:
      semaphore:
        semaphore_space_name: /tasklets/my-svc
        semaphore_name: deploy-lock
        weight: 1
```

Lifecycle: `enqueued` → `acquired` → `finished`

### Canary releases

Gradually roll out new builds:
```bash
# CLI: move label with percentage
ya tool tasklet label move stable --to <new_build_id> -p 50

# CI: via move-label task
input:
  details:
    label_name: stable
    build_meta: "${tasks.build.build.meta}"
    canary_release:
      percentage: 50
```

### Containers (Porto layers)

```yaml
spec:
  container:
    rootfs:
      porto:
        base_layer: sbr:123456        # Sandbox resource
        delta_layers:
          - sbr:789                   # Sandbox resource
          - art:<artifact-id>         # Artifact
          - layers:<ref>              # Layers reference
```

Arc sidecar requires FUSE support in custom containers.

### Requirements override

From CLI:
```bash
ya tool tasklet run stable input.json -r requirements.json
# requirements.json: { "container": { "cpu_limit": 2000 }, "account_name": "/root/..." }
```

From CI:
```yaml
runtime:
  tasklet:
    requirements:
      container:
        cpu_limit: 2000
        ram_limit: 2GB
```

Only fields marked `overridable: true` in t.yaml can be overridden.

### Logging

```bash
# View logs
ya tool tasklet execution logs <execution_id>

# Local run with logs
ya tool tasklet local run <binary> input.json --logs
```

Secrets are automatically scrubbed from logs.

For agents: grant "Log reader" role for TVM `tasklets-production` in your monium project.
