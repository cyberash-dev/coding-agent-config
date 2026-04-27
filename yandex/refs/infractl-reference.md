# infractl: Spec Reference

Read this file when working with `i.yaml` or any `i.<kind>.<name>.yaml` infractl configuration files.

## Core concepts

- **Namespace** (`i.yaml`) — project container, binds to ABC service. One K8s namespace = multiple Deploy projects/awacs namespaces
- **Runtime** — pod specification: compute, storage, replicas, image, networking, health checks. The most common object
- **Application** — app metadata: environments (TESTING/PRODUCTION), TVM, network macros
- **AwacsRouting** — HTTP routing: domains -> upstreams -> backend endpoints (L7 balancer)
- **ServiceEndpoint** — auto-generated from Runtime, used for service-to-service discovery

## File structure & naming

```
<namespace>/
├── i.yaml                        # Namespace metadata (required)
├── i.app.<name>.yaml            # Application definition
├── i.runtime.<name>.base.yaml   # Base runtime template (NOT deployed)
├── i.awacsrouting.<name>.yaml   # HTTP routing
├── i.alert.<name>.yaml          # Alert definitions
├── cfg.yaml                     # Config files to inject
├── package.json                 # Docker build manifest
├── prod/
│   ├── i.yaml                   # Prod environment metadata
│   └── i.runtime.<name>.yaml   # Prod runtime (inherits from base)
└── test/
    ├── i.yaml                   # Test environment metadata
    └── i.runtime.<name>.yaml   # Test runtime (inherits from base)
```

**Naming rules:**
- `i.yaml` — metadata/environment config
- `i.<kind>.<name>.yaml` — object specs
- `i.<kind>.<name>.base.yaml` — base templates (compiled but NOT deployed)
- Directory hierarchy = environment separation

## Inheritance

```yaml
# prod/i.runtime.backend.yaml
from: ../i.runtime.backend.base.yaml    # inherit from parent
spec:
  compute:
    memory: 500M                         # override specific fields
  replicas:
    sas: 3
    vla: 2
```

**Rules:**
- `from:` field references parent spec
- Parent must be at same level or higher in directory tree
- `i/` or `.i/` directories for cross-hierarchy templates (mixins)
- Deep merge: child overrides only specified fields, rest inherited
- File refs: `from: ${file-ref:path/to/base.yaml}`

## Namespace (i.yaml)

```yaml
# Root i.yaml
metadata:
  name: mynamespace               # required — K8s namespace name
spec:
  abc_slug: myservice             # required — ABC service slug
  deploy_project:
    mode: ENABLED                 # ENABLED | DISABLED
    project_id: my-deploy-proj    # Deploy project name

# Environment i.yaml (e.g., prod/i.yaml)
metadata:
  name: mynamespace
spec:
  abc_slug: myservice
```

## Runtime spec (most important object)

```yaml
# i.runtime.<name>.yaml
spec:
  # === COMPUTE (required) ===
  compute:
    memory: 500M                  # data_size (K, M, G, T) — pod memory
    vcpu: "1000"                  # string — thousandths of CPU (1000 = 1 core)
    net: 15M                      # data_size — network bandwidth guarantee
    net_limit: 30M                # optional — network bandwidth limit
    anon_memory_limit: 1G         # optional — anonymous memory limit

  # === STORAGE ===
  storage:
    storage_class: hdd|ssd        # disk type
    io_bandwidth: 30M             # IO bandwidth guarantee
    io_bandwidth_limit: 60M       # IO bandwidth limit
    quota: 1G                     # disk quota
    cwd_quota: 500M               # Nanny-specific
    snapshots: 5                  # Nanny-specific (min 3)
    storage_provisioner: shared|lvm  # Deploy-specific

  # === REPLICAS (3 options) ===

  # Option 1: Simple per-DC counts
  replicas:
    sas: 3
    vla: 2
    iva: 1
    myt: 1

  # Option 2: Per-cluster (Deploy only)
  per_cluster:
    replicas:
      sas:
        pods: 3
        max_unavailable:
          percent: 34
        deploy_speed:
          update_portion: 10
          min_delay: 30

  # Option 3: Multi-cluster
  multi_cluster:
    replicas:
      sas: 3
      vla: 2
    max_unavailable:
      percent: 40
    deploy_speed:
      update_portion: 10
      min_delay: 30

  # === FILESYSTEM ===

  # Docker image
  image: "${package:path/to/package.json}"
  # OR explicit: registry.yandex.net/app:tag@sha256:hash

  # Porto layers (alternative to Docker)
  layers:
    - id: base
      resource_id: "5785356017"
    - id: app
      resource_id: "${resource:path/to/build.json}"
  layer_refs: [base, app]
  layers_order_policy: FORWARD|REVERSE

  # Config file injection
  files:
    - src: cfg.yaml               # local file path
      dst: /configs/cfg.yaml      # path inside container
      mode: "0644"                # file permissions

  # === NETWORKING ===
  network_id: _SEARCHSAND_        # network macro (RackTables)
  resolv_conf: DEFAULT|KEEP|NAT64_LOCAL

  endpoint_sets:
    - port: 8080
      protocol: TCP
      tags: [http]

  # === TVM & SERVICE MESH ===
  provides:
    my_app:
      tvm:
        id: 1234567
        secret: "${sec-ID:ver-ID:tvmsecret}"

  consumes:
    target_service:
      tvm_id: 555555
    another_service:
      ref:
        endpoint: "namespace/service:app_name"

  # === HEALTH CHECKS ===
  readiness:
    http:
      any: true
      path: /health
      port: 8080
    tcp_check:
      port: 8080

  liveness:
    http:
      path: /alive
      port: 8080

  # === DEPLOYMENT STRATEGY ===
  deployment:
    strategy: PARALLEL|SEQUENTIAL|PARALLEL_WITH_APPROVE

  stage_type: SNAPSHOT             # vs simple Stage (Deploy only, cannot change after creation)

  # === MONITORING ===
  metrics:
    spec:
      endpoints_object: ${file-ref:path/to/i.metricendpoints.yaml}
      endpoints:
        - name: my-metrics

  alert_group:
    spec:
      alerts:
        my-alert:
          from: ${file-ref:path/to/i.alert.base.yaml}

  # === GPU (optional) ===
  gpu:
    enabled: true
    count: 1
    gpu_memory: 8G
```

## Secret references

```yaml
# Full form (pinned version)
"${sec-01gakdzvjeaxtx82tp8s0snb2a:ver-01gakdzvjn1t2113753k36bqfw:tvmsecret}"

# Short form (latest version)
"${sec-01gakdzvjeaxtx82tp8s0snb2a:tvmsecret}"

# File reference (for inheritance/templates)
"${file-ref:path/to/file.yaml}"

# Package reference (Docker/Sandbox artifact)
"${package:path/to/package.json}"

# Resource reference (Sandbox resource)
"${resource:path/to/build.json}"
```

## CLI commands

```bash
# Service lifecycle
ya tool infractl bootstrap [trial]       # create new service (interactive wizard)
ya tool infractl make [dir]              # compile specs locally
ya tool infractl build                   # build Docker/Sandbox artifacts
ya tool infractl diff [--artifacts]      # preview changes before deploy
ya tool infractl deploy [--artifacts]    # deploy to infrastructure
ya tool infractl status                  # check deployment status
ya tool infractl delete                  # remove service

# K8s operations
ya tool infractl put                     # apply specs to K8s directly
ya tool infractl pull <ns> <kind>/<name> # download objects from K8s

# Configuration
ya tool infractl kubeconfig setup        # configure K8s access
ya tool infractl kubeconfig use-context k.yandex-team.ru
ya tool infractl specs generalize        # extract common parts from specs

# Token delegation
ya tool infractl modify delegate yp -n <namespace>
ya tool infractl modify delegate awacs -n <namespace>
ya tool infractl modify delegate nanny -n <namespace>

# Import from existing services
ya tool infractl import application      # import Deploy project
ya tool infractl import stage <name>     # import Deploy stage
ya tool infractl import nanny <name>     # import Nanny service
ya tool infractl import awacsupstream -n <k8s_ns> <awacs_ns> <upstream>
```

### Key flags

| Command | Flag | Description |
|---------|------|-------------|
| `deploy` | `--artifacts` | include built artifacts |
| `deploy` | `--force` | skip safety checks |
| `deploy` | `--zero-diff` | force deploy despite no changes |
| `deploy` | `--fail-on-non-infractl-changes` | error if manual changes detected |
| `build` | `--incremental` | only rebuild missing artifacts |
| `build` | `-d package=image:tag@sha` | Docker reference |
| `build` | `-s package=resource_id` | Sandbox resource |
| `diff` | `--artifacts` | include artifact diffs |
| `diff` | `--file <path>` | specific files only |

## CI integration

### apply_specs tasklet (main CI cube)

```yaml
# In a.yaml flows
jobs:
  release:
    task: common/infractl/apply_specs
    input:
      config:
        source:
          arc:
            manifest: path/to/environment  # directory with i.yaml
        put:
          message: 'Release: ${context.title}'
          wait:
            enabled: true
          fail_on_non_infractl_changes: true
```

### deploy_objects cube (auto-generates deploy graph)

```yaml
jobs:
  cd:
    task: common/cd/deploy_objects
    input:
      config:
        specs:
          - path/to/i.runtime.prod.yaml
          - path/to/i.awacsrouting.yaml
        arc_commit: ${context.target_revision.hash}
        diff_mode: K8S|DEFAULT|END_SYSTEM
```

### Required CI secrets (in YAV)

| Key | Purpose | OAuth client_id |
|-----|---------|----------------|
| `infractl_ci.kubetoken` | K8s access | `141d6d975f6049789ba7c78bf82ada5d` |
| `infractl_ci.docker_token` | Docker push | `12225edea41e4add87aaa4c4896431f1` |
| `infractl_ci.yav_token` | Vault access | `ce68fbebc76c4ffda974049083729982` |

### Rollback support

```yaml
# Save specs for rollback (in release cube)
release:
  input:
    config:
      output_resource_ttl: 365  # days

# Rollback cube
rollback:
  if: ${context.flow_type == 'ROLLBACK'}
  input:
    config:
      source:
        sandbox_resource:
          matcher:
            job: release
```

## Limitations

- Trial mode: 14-day auto-deletion, 0.3 CPU, 3 pods max
- Single robot per namespace per system (YP, awacs, Nanny)
- Cannot change `stage_type` after creation
- `per_cluster` replicas not supported in Nanny
- Max one a.yaml per directory
