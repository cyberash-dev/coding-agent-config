# infractl: Object Types Reference

Companion to infractl-reference.md. Read when working with non-Runtime infractl objects.

## Easy mode objects (user-facing)

### Runtime
Pod specification — the most common object. See infractl-reference.md for full schema.
- File: `i.runtime.<name>.yaml`
- Maps to: DeployStage (Deploy) or NannyService (Nanny)

### RuntimeGroup
Multiple runtimes in a single Deploy stage (multi-unit).
- File: `i.runtimegroup.<name>.yaml`
- Auto-assembled from multiple Runtime files in same directory
- Allows per-unit deployment control

### Application
Application metadata and environment configuration.
- File: `i.app.<name>.yaml`
```yaml
spec:
  abc_slug: myservice
  environments:
    TESTING: {}
    PRODUCTION: {}
  deploy_project:
    mode: ENABLED
    project_id: my-deploy-project
  tvm:
    id: 1234567                   # per-environment TVM
  network_macros:
    - _MY_MACRO_
```

### ServiceEndpoint
Service discovery and mesh configuration.
- Auto-generated from Runtime `provides`/`consumes`
- Exports TVM apps and endpoint sets
- Used for service-to-service communication

### AwacsEasyBalancer
L7 balancer namespace (awacs).
- File: `i.awacseasybalancer.<name>.yaml`
```yaml
spec:
  abc_slug: myservice
  locations:
    - sas
    - vla
  cert_order:
    common_name: myapp.yandex.net
    subject_alternative_names:
      - myapp.yandex-team.ru
```

### AwacsRouting
HTTP routing rules — domains to upstreams (backends).
- File: `i.awacsrouting.<name>.yaml`
```yaml
spec:
  domains:
    - name: myapp.yandex.net
      certificates: [auto]       # auto-order TLS cert
  upstreams:
    backend:
      endpoints:
        - ref:
            endpoint: mynamespace/prod-backend:web
          weight: 100
      health_check:
        http:
          path: /ping
          expected_codes: [200]
    api:
      endpoints:
        - ref:
            endpoint: mynamespace/prod-api:http
          weight: 100
      matching:
        path:
          prefix: /api/
```
- Translates to: AwacsEasyDomain + AwacsUpstream(s)

### AwacsEasyUpstream
Standalone upstream definition.
- File: `i.awacseasyupstream.<name>.yaml`
- Use for multi-domain upstreams or when routing is complex
```yaml
spec:
  upstream_id: my-upstream
  backends:
    - ref:
        endpoint: ns/runtime:port_tag
      weight: 100
```

### RolesConfiguration
Access control for infractl objects.
- File: `i.rolesconfiguration.<name>.yaml`
```yaml
spec:
  roles:
    - name: developer
      permissions:
        - object_kind: Runtime
          mode: write
        - object_kind: AwacsRouting
          mode: read
```

### Namespace
Project container (top-level i.yaml). See infractl-reference.md.

## Hard mode objects (low-level, usually auto-generated)

### DeployStage
Internal Deploy representation. Generated from Runtime.
- File: `i.deploystage.<name>.yaml`
- Use only for features not exposed in Runtime

### NannyService
Internal Nanny representation. Generated from Runtime.
- File: `i.nannyservice.<name>.yaml`
- Manages spec + allocation + activation

### AwacsUpstream
Low-level awacs upstream. Use AwacsEasyUpstream or AwacsRouting instead.
- File: `i.awacsupstream.<name>.yaml`

### AwacsBackend
Low-level awacs backend endpoint group.
- File: `i.awacsbackend.<name>.yaml`
- Supports MANUAL backend type

### AwacsEasyDomain
Simplified certificate + domain management.
- File: `i.awacsdomain.<name>.yaml`
- Auto-orders TLS certificates

## Monitoring objects

### alert
Monitoring alert definition.
- File: `i.alert.<name>.yaml`
```yaml
spec:
  project_id: my-monitoring-project
  name: "${parameters.cluster} 5xx errors"
  type: EXPRESSION
  expression: ...
  window: 300
  delay: 60
  parameters:
    cluster: prod
  notification_channels:
    - id: my-channel
```
- Can be standalone or embedded in Runtime via `alert_group`
- Supports templating with `parameters`

### MetricEndpoints (metric)
Metric collection endpoint definition.
- File: `i.metricendpoints.<name>.yaml`
```yaml
defaults:
  metrics_ttl: 2d
spec:
  endpoints:
    metrics:
      pull:
        url: http://{host}:3400/metrics
        format: PROMETHEUS
```
- Referenced from Runtime via `metrics.spec.endpoints_object: ${file-ref:...}`

### notificationchannel
Alert notification routing.
- File: `i.notificationchannel.<name>.yaml`
```yaml
spec:
  project_id: my-project
  name: my-channel
  method:
    telegram:
      chat_id: "-123456789"
```

## Other objects

### Beta
Beta testing / canary deployment configuration.
- Per-commit beta slots, hash ring allocation

### TVM
TVM application management.
- File: `i.tvm.<name>.yaml`
- Create or reference TVM apps, manage secrets

### Certificate
TLS certificate management.
- File: `i.certificate.<name>.yaml`
- Domain certificates, SAN support, auto-renewal

### Warden
IP/network security rules (firewall).
- File: `i.warden.<name>.yaml`

### PuncherRuleSet
Network access rules (interconnect, cross-DC traffic).
- File: `i.puncherruleset.<name>.yaml`

### JugglerAggregate
Monitoring aggregation (multi-state alerts, SLA tracking).
- File: `i.juggleraggregate.<name>.yaml`

### Logbroker
Log collection and routing configuration.
- File: `i.logbroker.<name>.yaml`

### MDBEasyPostgres
Managed PostgreSQL database instance.
- File: `i.mdbeasypostgres.<name>.yaml`

### Manifest
Build manifest reference (Docker or Porto).
- File: `i.manifest.<name>.yaml`
- Usually `package.json` is used directly instead

### Macro
Network macro management (RackTables).
- File: `i.macro.<name>.yaml`
