# Arcadia CI: a.yaml Schema Reference

Read this file when working with a.yaml CI configuration files.

## Top-level structure

```yaml
service: <abc-slug>        # string, required — ABC service slug
title: <display-name>      # string, required — project display name
ci:
  secret: sec-XXXXXX       # string — Yandex Vault secret ID (must contain ci.token key)
  runtime: {}              # runtime_config — default runtime for all jobs
  actions: {}              # map<string, action> — action definitions
  flows: {}                # map<string, flow> — flow definitions
  releases: {}             # map<string, release> — release definitions
  diff-actions: {}         # map<string, diff_action> — diff-action definitions
  permissions: {}          # access control settings
  notifications: {}        # notification settings
  autocheck: {}            # autocheck settings (large tests, etc.)
  flow-engine-version: 2   # integer — flow engine version
  release-title-source: flow-vars  # enum: flow-vars
  pci-dss: {}              # PCI DSS settings
  additional-secrets: []   # array<string> — extra vault secret IDs
```

**Rules**: max file size 8MB. One a.yaml per directory, applies recursively to subdirectories. Validated with `ya tool ci validate`.

## Flow

```yaml
flows:
  <flow-id>:
    title: string                    # display name
    description: string              # optional
    jobs: {}                         # map<string, job> — required
    cleanup-jobs: {}                 # map<string, job> — cleanup tasks
    flow-layout: default|graphviz    # UI layout
    show-in-actions: bool            # show flow in action list
```

## Job (task in a flow)

```yaml
jobs:
  <job-id>:
    title: string                      # display name
    description: string                # optional
    task: <registry/path>              # string, required — task from /ci/registry/
    needs: [job-id, ...]               # array<string> — dependencies
    needs-type: all                    # enum: all|any|fail|any-success|all-complete|all-success
    # all (default) — all deps must succeed
    # any — at least one dep must succeed
    # fail — at least one dep must fail
    # any-success — at least one dep succeeded (others may still run)
    # all-complete — all deps finished (regardless of status)
    # all-success — all deps must succeed (alias for all)

    stage: <stage-id>                  # string — release stage reference
    input:                             # object — task parameters
      config:
        key: value                     # supports ${expression} (JMESPath)
    context-input: {}                  # object — extra context for expressions

    # Execution control
    if: <jmes-expression>              # string — conditional execution
    kill-timeout: 1h                   # duration — max execution time
    manual:                            # manual approval gate
      enabled: true                    # bool
      prompt: "Approve deploy?"        # string — confirmation message
    attempts:                          # retry configuration
      max: 3                           # integer — max attempts (Sandbox)
      on-fail: run_new                 # enum: run_new|restart (Sandbox)
      on-timeout: run_new              # enum: run_new|restart (Sandbox)
      backoff:                         # delay between retries
        initial-delay: 10s             # duration
        max-delay: 5m                  # duration
        multiplier: 2.0                # float

    # Resource requirements (Sandbox)
    requirements:
      cores: 4                         # integer
      ram: 8GB                         # data_size
      disk: 100GB                      # data_size
      tmpfs: 300MB                     # data_size
      sandbox:                         # Sandbox-specific
        container_resource: N          # integer — LXC container
        porto_layers: [N]              # array<integer> — Porto layers
        client_tags: "SSD"             # string
        dns: default|local|dns64       # enum
        host: "hostname"               # string
        platform: "linux"              # string
        privileged: false              # bool
        cpu_model: "E5-2660 v4"        # string
        semaphores:                    # concurrency limits
          acquires:
            - name: MY_SEM             # required
              capacity: 5              # min: 1
              weight: 1                # min: 1
              public: false            # bool
        priority:
          class: SERVICE               # enum: USER|SERVICE|BACKGROUND
          subclass: NORMAL             # enum: LOW|NORMAL|HIGH
        tasks_resource: N              # resource with task binary
        tasks_resource_query:          # search for task binary
          owner: GROUP
          release: stable
          attrs: {}

    runtime: {}                        # per-job runtime override

    # Task generation
    multiply:
      by:                              # array — values to iterate over
        - key1: val1
        - key1: val2
      title: "Job for ${multiply.key1}" # template for job title
      input:                           # template for job input
        config:
          param: "${multiply.key1}"

    # Metadata
    tags: [string]                     # arbitrary tags
    version: N                         # integer — task version
    permissions: {}                    # per-job permissions
```

## Action

```yaml
actions:
  <action-id>:
    title: string                      # display name
    description: string                # optional
    flow: <flow-id>                    # string, required — flow to run
    triggers:                          # array — when to run
      - on: pr                         # enum: pr|commit
        into: trunk                    # target branch
        filters:                       # optional path/metadata filters
          sub-paths: ['src/**']
          abs-paths: ['path/from/root/**']
        flow-vars:                     # override flow variables
          key: value
    schedule:                          # cron-like schedule
      cron: "0 */6 * * *"             # cron expression
    flow-vars: {}                      # default flow variables
    flow-vars-ui: {}                   # UI-configurable variables

    # PR behavior
    cleanup:                           # cleanup on PR events
      conditions:
        - reasons: [new-diff-set]      # enum (see below)
          cleanup: true                # run cleanup-jobs
          interrupt: false             # stop main flow
      delay: 5m                        # duration — wait before cleanup
      on-status: [SUCCESS, FAILURE]    # which statuses trigger cleanup

    # Limits
    max-active: 5                      # max concurrent executions
    max-active-policy: cancel_oldest|fail_newest  # enum
    max-start-per-minute: 10           # rate limit
    quiet-period: 30s                  # duration — debounce

    # Advanced
    binary-search: {}                  # bisection config
    notifications: {}                  # notification overrides
    default-config-source: pr|trunk    # which a.yaml version to use
    tags: [string]                     # metadata tags
    requirements: {}                   # override requirements
    runtime: {}                        # override runtime
    permissions: {}                    # override permissions
```

**Cleanup reason types**: `new-diff-set`, `pr-merged`, `pr-discarded`, `finish`, `cancel`, `diff-set-revisited`

## Release

```yaml
releases:
  <release-id>:
    title: string                      # display name
    description: string                # optional
    flow: <flow-id>                    # string, required
    stages:                            # array — sequential stages
      - id: build                      # string, required
        title: "Build"                 # string
        displace: true                 # bool — allow displacement
    filters:                           # which commits trigger release
      sub-paths: ['**']
    auto: true                         # bool — autorelease on commit

    # Advanced
    flow-vars: {}                      # flow variables
    manual: false                      # bool — manual trigger only
    max-active: 1                      # max concurrent releases
    cycle-mode: false                  # bool
    single-stage-mode: false           # bool
    cleanup:
      reasons: [cancel]               # enum: finish|cancel (default: cancel)
    hotfix: {}                         # hotfix configuration
    rollback: {}                       # rollback configuration
    default-promotion-flow: <flow-id>  # flow for stage promotion
    notifications: {}                  # notification overrides
    requirements: {}                   # override requirements
    runtime: {}                        # override runtime
    permissions: {}                    # override permissions
    tags: [string]                     # metadata tags
```

## Runtime config (default for all jobs)

```yaml
ci:
  runtime:
    sandbox-owner: GROUP_NAME         # string, required — Sandbox quota group
    sandbox:
      owner: GROUP_NAME               # override per-runtime
      kill-timeout: 2h                # duration
      container_resource: N           # LXC container
      porto_layers: [N]              # Porto layers
      headers: {}                     # key-value headers
      tags: [string]                  # Sandbox tags
      hints: {}                       # execution hints
      priority:                       # Sandbox priority
        class: SERVICE
        subclass: NORMAL
    tasklet:                          # Tasklet v2 config
      account_name: string            # execution account
      headers: {}
      tags: [string]
      requirements:
        container:
          cpu_limit: 4
          ram_limit: 8GB
          workdir:
            type: ssd                 # enum: hdd|ssd|ram
            space: 50GB
          network:
            name: string
          rootfs: {}
          tmpfs: {}
    get-output-on-fail: false         # bool — fetch output from failed jobs
    download-resources: true          # bool
    json-serializer: standard         # enum: legacy|standard
    reuse:                            # result reuse config
      enabled: false                  # bool
      matching: [commit, version, job-launch-number]
      running: false                  # reuse from running jobs
      resource-types: []              # which resource types
      cancel-policy: continue-other   # enum: continue-other|cancel-all
```

## Expressions

Syntax: `${expression}` using JMESPath. Testable in CI UI (JMESPath tab).

Available in: `input`, `context-input`, task registry definitions.

Context variables include flow context, flow-vars, job results from upstream jobs.

## YAML reuse

```yaml
# Anchors (standard YAML)
_defaults: &defaults
  requirements:
    cores: 4
    ram: 8GB

flows:
  my-flow:
    jobs:
      job1:
        <<: *defaults
        task: my/task
```

Also supports `includes` from other a.yaml files and `extends` for inheritance.

## Minimal working example

```yaml
service: my-service
title: My Project CI
ci:
  secret: sec-XXXXXX
  runtime:
    sandbox-owner: MY_GROUP
  actions:
    check:
      title: "PR Check"
      flow: check-flow
      triggers:
        - on: pr
          into: trunk
  flows:
    check-flow:
      title: "Check"
      jobs:
        build:
          title: "Build"
          task: common/arcadia/ya_build
          input:
            config:
              targets: my/project
        test:
          title: "Test"
          task: common/arcadia/ya_test
          needs: [build]
          input:
            config:
              targets: my/project
```

## Multi-stage release example

```yaml
service: my-service
title: My Project
ci:
  secret: sec-XXXXXX
  runtime:
    sandbox-owner: MY_GROUP
  releases:
    production:
      title: "Production Release"
      flow: deploy
      auto: true
      filters:
        sub-paths: ['**']
      stages:
        - id: build
          title: "Build"
        - id: testing
          title: "Testing"
        - id: production
          title: "Production"
  flows:
    deploy:
      jobs:
        compile:
          title: "Compile"
          task: common/arcadia/ya_build
        test:
          title: "Test"
          needs: [compile]
          task: common/arcadia/ya_test
        deploy-testing:
          title: "Deploy to Testing"
          stage: testing
          needs: [test]
          task: common/deploy/nanny
          manual:
            enabled: true
            prompt: "Deploy to testing?"
        deploy-prod:
          title: "Deploy to Production"
          stage: production
          needs: [deploy-testing]
          task: common/deploy/nanny
          manual:
            enabled: true
            prompt: "Deploy to production?"
```

## CLI tools

```bash
ya tool ci validate [path/to/a.yaml]     # validate config syntax
ya tool ci generate [path/to/a.yaml]     # render full config (resolve includes)
ya tool ci delegate [path] <branch>      # delegate vault access to branch
ya tool ci layout (default|graphviz) <flow-id>  # change flow layout
```

Requirements: macOS/Linux, inside Arcadia repo, internal network.
