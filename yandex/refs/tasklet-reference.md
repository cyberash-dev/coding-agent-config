# Tasklet v2 — Platform Reference

## Overview

Tasklets are a multilingual platform for running automated tasks in cloud environments. Used for builds, testing, data processing, and CI/CD. Recommended way to create operations for Arcadia CI.

Tasklets replaced Sandbox tasks. They work as executables: receive input, process it, return result via protobuf.

**Languages**: Python, Java, Go, Node.js, Swift (any language in general)

**Key advantages**:
- Multi-language support (vs Python-only Sandbox)
- Flexible runtimes (YT, Sandbox, YP) — SDK separated from runtime
- Protobuf-based I/O — type safety + schema compatibility
- Sidecars — stable API for Arcadia, secrets, artifacts
- Labels — instant version switching
- Unit testing support, project generation via `ya project create`

**Web UI**: https://tasklets.yandex-team.ru

---

## Key Concepts

| Concept | Description |
|---------|-------------|
| **Namespace** | Logical grouping for tasklets (like a project scope). One per ABC service recommended |
| **Tasklet** | Registered executable with metadata and spec. Lives in a namespace |
| **Build** | Published version of tasklet binary + schema. Stored in Sandbox |
| **Label** | Named pointer to a Build (e.g. `stable`, `latest`, `dev-<user>`). Labels can be moved between builds instantly |
| **Execution** | Single run of a tasklet. Has status, input, output, logs |
| **Account** | Quota container (CPU/RAM) with tree structure. Determines runtime resources |
| **Network** | Named network macro defining firewall rules for tasklet execution |
| **Tag** | Metadata key-value pairs attached to executions for filtering |
| **Contract** | Binary or package launch protocol — how tasklet receives args and returns results |

---

## t.yaml Full Spec

Tasklet spec file. Default name: `t.yaml`. Two sections: `meta` + `spec`.

### meta section

```yaml
meta:
  name: my_tasklet              # [a-zA-Z][-_a-zA-Z0-9]{1,63}
  description: "What it does"   # free text
  namespace: my-namespace       # namespace name
  catalog: /project/tasklets    # visual tree location in UI
  service: my-abc-service       # responsible ABC service (no ACL effect)
  doc_link:
    url: https://docs.yandex-team.ru/...
  support_links:
    - url: https://forms.yandex-team.ru/...
```

To apply meta changes: `ya tool tasklet tasklet update`

### spec section

```yaml
spec:
  executor:
    type: binary          # binary | tgz | zstd | tar

  container:
    cpu_limit: 1000       # millicores (1000 = 1 CPU)
    ram_limit: 1GB        # RAM limit
    workdir:
      type: ssd           # ssd | ram
      space: 1GB          # disk size
    tmpfs:
      space: 500MB        # tmpfs size (≤ ram_limit, 0 = disabled)
    network:
      name: _TASKLETS_SERVICE_MY_NETS_    # network macro name
    rootfs:               # custom containers
      porto:
        base_layer: sbr:123       # base porto layer (sandbox resource)
        delta_layers:             # list of delta layers
          - sbr:456
          - art:789               # or artifact reference
          - layers:ref            # or layers reference

  proto_schema:           # Schema Registry (recommended)
    path: project/path/proto      # Arcadia path to PROTO_SCHEMA()
    input_message: pkg.InputMsg   # full proto message name
    output_message: pkg.OutputMsg

  sidecars:
    arc: true
    ci: true
    secrets: true
    sandbox_resources: true
    artifacts: true
    xcode: true
    mount: true

  execution_timeout: 3600   # seconds, default=3600, max=604800 (7 days)
  interruption_timeout: 60  # seconds for graceful shutdown (< execution_timeout)
  idempotent: false         # allow auto-restart on infra errors
  deprecated: false         # mark as deprecated
  version: 1                # contract version (0=sandbox default, 1=YT default since 2025-03-04)
```

Spec changes require: new build upload → label move.

### requirements_options

Allows overriding fields at run time:

```yaml
spec:
  requirements_options:
    container:
      cpu_limit:
        overridable: true
        min_value: 1000
        max_value: 4000
      ram_limit:
        overridable: true
        min_value: 1GB
        max_value: 4GB
      workdir:
        type: { overridable: true }
        space: { overridable: true, min_value: 1GB, max_value: 4GB }
      tmpfs:
        space: { overridable: true, min_value: 0, max_value: 1GB }
      network:
        name: { overridable: true }
      rootfs:
        porto:
          base_layer: { overridable: true }
          delta_layers:
            override_type: allow_override  # allow_override | allow_append | not_overridable
    execution_timeout:
      overridable: true
      min_value: 600
      max_value: 7200
```

---

## Contract

### Binary type (`type: binary`)

```shell
./tasklet executorAddress inputFile outputFile errorFile
```

- `executorAddress` — IPv6 gRPC address of `ExecutorService`
- `inputFile` — path to input protobuf binary
- `outputFile` — path for output protobuf binary
- `errorFile` — path for error protobuf (`UserError`)

### Package types (`type: tgz | zstd | tar`)

Archive with `run.sh` at root level. Steps:
1. Unpack archive
2. Run `./run.sh executorAddress inputFile outputFile errorFile`

### Result handling

Three outcomes:
1. **Success** → write output to `outputFile` (exit 0)
2. **Controlled error** → write `UserError` to `errorFile` (exit 0). Set `is_transient=true` for retryable errors
3. **Uncontrolled error** → non-zero exit code → `ServerError`

Algorithm: check exit code → check `errorFile` → read `outputFile`.

Cannot write to both files — `errorFile` takes priority.

### ServerError codes

| Code | Description |
|------|-------------|
| `ERROR_CODE_GENERIC` | Internal service error |
| `ERROR_CODE_ABORTED` | Externally aborted (e.g. CI cancellation) |
| `ERROR_CODE_NO_RESPONSE` | No response from executor process |
| `ERROR_CODE_CRASHED` | Non-zero exit code |
| `ERROR_CODE_TIMEOUT` | Exceeded execution_timeout |
| `ERROR_CODE_BAD_OUTPUT` | Contract violation (missing/empty/wrong type output) |
| `ERROR_CODE_RUNTIME_SERVICE_ERROR` | Runtime error (e.g. memory limit exceeded) |
| `ERROR_CODE_RUNTIME_EVICTION` | Runtime evicted the tasklet for scheduling reasons |

---

## Runtimes

| Feature | YT (default) | Sandbox | YP |
|---------|-------------|---------|-----|
| **Isolation** | Strict (CPU/RAM) | Soft (overcommit) | Strict (CPU/RAM) |
| **PCI DSS** | No | No | Yes |
| **Custom network** | Yes | No | Yes |
| **macOS** | No | Yes | No |
| **Custom containers** | Yes | Limited | Yes |
| **Start speed** | Moderate | Fast | Slow |
| **Default network** | `_YT_JOBS_TASKLETS_PRODUCTION_NETS_` | `_CMSEARCHNETS_` | `_TASKLETS_SECURE_NETS_` |

### Account naming by runtime

- YT: `/root/generic/{abc_slug}` (+ sub-accounts)
- YP: `/root/secure/{abc_slug}`
- Sandbox: `/root/sandbox/{generic|mobile_monorepo}/{linux|darwin}`

---

## Accounts & Quotas

### Tree structure

```
/root
├── generic/          → YT runtime
│   └── {abc_slug}/   → base account (visible in ABCD)
│       └── production/
│       └── testing/
├── secure/           → YP runtime
│   └── {abc_slug}/
└── sandbox/          → Sandbox runtime
    ├── generic/
    │   ├── linux
    │   └── darwin
    └── mobile_monorepo/
        └── darwin
```

### Quotas

- **Resources**: CPU + RAM
- Children cannot exceed parent's total
- Default limits: `RunningExecutionsLimit=50`, `TotalExecutionsLimit=5000`
- Order both via ABCD (running) / support ticket (total)

### Scheduling (HDRF)

- Strict quotas — only running tasklet consumption counted
- Overcommit allowed when cluster has free resources
- No eviction mechanism currently
- At DC loss — proportional resource reduction based on account quotas

### Creating accounts

1. Go to ABC service → Quotas → "Create account in provider" → Provider "Tasklets"
2. Name = ABC slug
3. Choose space: "Main" (YT) or "Secure" (YP)
4. Sub-accounts: create in UI https://tasklets.yandex-team.ru/accounts

---

## Schema Registry

### proto_schema (recommended)

```yaml
spec:
  proto_schema:
    path: project/path/to/proto     # path to PROTO_SCHEMA() macro
    input_message: pkg.InputMessage
    output_message: pkg.OutputMessage
```

- Stored in Schema Registry (efficient, deduped)
- FORWARD compatibility check on label moves
- Force move: `ya tool tasklet label move <label> --to <build_id> --compatibility-level none`

### naive_schema (deprecated)

```yaml
spec:
  naive_schema:
    input_message: pkg.InputMessage
    output_message: pkg.OutputMessage
```

- Stored in Tasklets service directly
- No compatibility checks
- Not recommended

---

## CLI Reference

Tool: `ya tool tasklet` (or build `tasklet-tool` from `arcadia/tasklet/cli`)

### Auth

Token lookup order:
1. `TASKLET_TOKEN` env var
2. `~/.tasklet/token` file
3. Auto-generated from SSH via `library/python/oauth`

### Common args

```
-f, --file <t.yaml>             # path to tasklet descriptor
-o, --output [json|yaml|table]  # output format (default: table)
-c, --cluster [local|env|test|prod]  # server instance
```

### namespace

```bash
ya tool tasklet namespace create <name> [-d "description"]
ya tool tasklet namespace get <name>
ya tool tasklet namespace list
ya tool tasklet namespace update <name> [-d "description"]
```

### tasklet

```bash
ya tool tasklet tasklet create [-f t.yaml]       # register from t.yaml
ya tool tasklet tasklet get <ns/tasklet>
ya tool tasklet tasklet list [<namespace>]
ya tool tasklet tasklet update [-f t.yaml]        # update meta from t.yaml
```

### build

```bash
ya tool tasklet build upload <file> --build-schema [--label <label>]
ya tool tasklet build upload <file> --schema-id <id>
ya tool tasklet build create ...                  # register using existing resource ID
ya tool tasklet build get <build_id>
ya tool tasklet build list [<ns/tasklet>] [-l limit] [-pt page]
```

Multi-platform upload:
```bash
ya tool tasklet build upload --build-schema \
  --linux-x86_64-platform <path> \
  --darwin-arm64-platform <path> \
  --darwin-x86_64-platform <path> \
  --label "dev-$(whoami)"
```

### label

```bash
ya tool tasklet label create [<ns/tasklet>:]<label> [-b <build_id>]
ya tool tasklet label get [<ns/tasklet>:]<label>
ya tool tasklet label list [<ns/tasklet>] [--temp]
ya tool tasklet label move [<ns/tasklet>:]<label> --to <build_id|label>
ya tool tasklet label move <label> --to <build_id> -p 50  # canary: 50%
```

### run

```bash
ya tool tasklet run [<ns/tasklet>:]<label> <input.json> [-i json|binary]
  [--account <account>]
  [--sandbox-owner <group>]
  [--unit <unitspace:unit>]           # run on agent
  [-r requirements.json]              # override requirements
  [--tag <tag>]                       # execution tags
  [-d]                                # auto-delegate secrets
```

### execution

```bash
ya tool tasklet execution get <execution_id>
ya tool tasklet execution list [<ns/tasklet>]
ya tool tasklet execution get-input <execution_id>
ya tool tasklet execution get-output <execution_id>
ya tool tasklet execution logs <execution_id>
ya tool tasklet execution abort <execution_id>
ya tool tasklet execution tag create <execution_id> <key>=<value>
ya tool tasklet execution tag delete <execution_id> <key>
ya tool tasklet execution tag list <execution_id>
```

### local run

```bash
ya tool tasklet local run <binary> <input.json> [--logs]
  [--account <account>] [--sandbox-owner <group>]
  [--tag <tag>]

# With public schema:
ya tool tasklet local run <binary> <input.json> --public-schema
# With local schema:
ya tool tasklet local run <binary> <input.json> --local-schema <path>
```

### delegation (secrets)

```bash
ya tool tasklet delegation create --secret_uuid <sec-ID> [--type user|ci] [--source <user|path>]
ya tool tasklet delegation list secret <sec-ID>
ya tool tasklet delegation list source [<source>] [--type user|ci]
ya tool tasklet delegation delete --token_uuid <tid-ID>
```

### schema

```bash
ya tool tasklet schema message-example [<ns/tasklet>:]<label> [-o json|yaml]
ya tool tasklet schema nirvana-template [<ns/tasklet>:]<label> [-o json|yaml]
```

### shell (remote debug)

```bash
ya tool tasklet shell start <execution_id>
```

### agent

```bash
ya tool tasklet agent run --unit <unitspace:unit> --agent-type single_subprocess
```

### semaphore

```bash
ya tool tasklet semaphore semaphore-space create <path> --service <abc>
ya tool tasklet semaphore semaphore create <space:name> --capacity <N>
```

### account, network, artifact

```bash
ya tool tasklet account ...        # manage accounts
ya tool tasklet network create/get/list/update
ya tool tasklet artifact get/list/delete/update-expired
ya tool tasklet artifact sandbox upload/create
```

### unitspace & unit (agents)

```bash
ya tool tasklet unitspace create <name> --service <abc>
ya tool tasklet unit create <unitspace:unit>
```
