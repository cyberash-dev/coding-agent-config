# Yandex Cloud Platform & yc CLI Reference

## Overview

Yandex Cloud is a public cloud platform. Resource hierarchy:

**Organization → Cloud → Folder → Resource**

- **Organization**: Top-level container for clouds and users
- **Cloud**: Contains folders, belongs to organization
- **Folder**: Contains resources (VMs, disks, buckets, etc.)
- **Resource**: Individual items — access permissions inherit from parent to child

---

## yc CLI Setup

### Installation

```bash
# Interactive install (Linux/macOS)
curl https://storage.yandexcloud.net/yandexcloud-release/install.sh | bash

# Non-interactive with options
curl https://storage.yandexcloud.net/yandexcloud-release/install.sh | \
    bash -s -- -i /opt/yc -a   # -i install dir, -a auto-modify rc, -n skip rc
```

Add to shell rc (`~/.bashrc` / `~/.zshrc`):
```bash
if [ -f "$HOME/yandex-cloud/path.bash.inc" ]; then source "$HOME/yandex-cloud/path.bash.inc"; fi
if [ -f "$HOME/yandex-cloud/completion.zsh.inc" ]; then source "$HOME/yandex-cloud/completion.zsh.inc"; fi
```

### First run

```bash
yc init   # interactive wizard: token, cloud, folder, zone
```

### Update & version

```bash
yc version              # show version
yc components update    # update to latest
yc components restore   # rollback to previous
```

### Uninstall

```bash
rm -rf ~/yandex-cloud ~/.config/yandex-cloud
```

---

## yc CLI Core

### Command structure

```bash
yc <service_group> <resource_type> <action> [--flag value]
# Example: yc compute instance create --name my-vm
```

### Global flags

| Flag | Description |
|------|-------------|
| `--profile <name>` | Use specific profile |
| `--cloud-id <id>` | Override cloud |
| `--folder-id <id>` | Override folder |
| `--folder-name <name>` | Override folder by name |
| `--format <fmt>` | Output: `text` (default), `yaml`, `json`, `json-rest` |
| `--debug` | Debug logs |
| `--debug-grpc` | Detailed gRPC logs |
| `--async` | Return operation ID immediately |
| `--no-user-output` | Suppress user output from stderr |
| `--impersonate-service-account-id <id>` | Act as service account |
| `-h`, `--help` | Help for any command |

### Output formats

```bash
yc vpc network list                  # default text table
yc vpc network list --format yaml    # YAML
yc vpc network list --format json    # JSON
yc config set format yaml            # set default format
```

### Async operations

```bash
yc compute instance create ... --async   # returns operation ID immediately
yc operation get <operation_ID>          # check status
yc operation wait <operation_ID>         # wait for completion
```

### Environment variables

```bash
export YC_IAM_TOKEN="<token>"                            # auto-auth
export HTTPS_PROXY="https://user:pass@hostname:port"     # proxy
```

---

## Profile Management

```bash
yc config profile create <name>      # create empty profile (auto-activates)
yc config profile list               # list all (ACTIVE marked)
yc config profile get <name>         # show profile params
yc config profile activate <name>    # switch active profile
yc config profile delete <name>      # delete (cannot delete active/last)

yc config list                       # show current profile config
yc config set <param> <value>        # set param (token, cloud-id, folder-id, etc.)
yc config unset <param>              # remove param
yc config get <param>                # get single param value
```

Key params: `token`, `service-account-key`, `cloud-id`, `folder-id`, `folder-name`, `organization-id`, `format`

Mutually exclusive: `folder-id` / `folder-name`, `token` / `service-account-key` (last set wins)

---

## Authentication Methods

### 1. Yandex Account (OAuth token)

```bash
yc config set token <OAuth_token>    # lifetime ~1 year
```

### 2. Federated Account (SSO)

```bash
yc init --federation-id=<federation_ID>   # opens browser for IdP auth
```

### 3. Service Account — Authorized Key

```bash
yc config set service-account-key path/to/key.json
```

### 4. Service Account — Impersonation (recommended)

```bash
yc storage bucket create --name my-bucket \
  --impersonate-service-account-id <sa_ID>
```

No long-lived credentials stored locally.

### 5. VM Metadata (for apps on Yandex Cloud VMs)

Attach SA to VM — CLI/SDK auto-fetches IAM token from `http://169.254.169.254/metadata/v1/`. No config needed.

---

## IAM (Identity and Access Management)

### Roles

**Primitive** (all resource types): `admin`, `editor`, `viewer`, `auditor`

**Service** (per-service): format `service.resources.role` (e.g. `compute.images.user`)

Roles inherit from parent to child resources. Custom roles not supported.

### Service Accounts

```bash
yc iam service-account create --name my-robot
yc iam service-account list
yc iam service-account get --id <sa_ID>
yc iam service-account delete --id <sa_ID>
```

### Keys

| Type | Purpose | Command |
|------|---------|---------|
| **Authorized key** | Get IAM tokens (RSA, JSON file) | `yc iam key create --service-account-name <name>` |
| **API key** | Simplified auth (no expiry by default) | `yc iam api-key create --service-account-name <name> --scopes <scope>` |
| **Static access key** | AWS-compatible APIs (S3, MQ, YDB) | `yc iam access-key create --service-account-name <name>` |

API key scopes: `yc.compute.readOnly`, `yc.ai.foundationModels.execute`, `yc.monitoring.manage`, `yc.serverless.functions.invoke`, etc.

### Tokens

| Type | Lifetime | Usage |
|------|----------|-------|
| **IAM token** | 12 hours max | `Authorization: Bearer <token>` — primary auth method |
| **OAuth token** | ~1 year | Exchanged for IAM token via CLI/API |

```bash
yc iam create-token     # get IAM token for current profile
yc iam token revoke      # revoke token
```

### Access Bindings (role assignment)

```bash
# Assign role to user on folder
yc resource-manager folder add-access-binding \
  --id <folder_ID> --role editor --user-account-id <user_ID>

# Assign role to SA
yc resource-manager folder add-access-binding \
  --id <folder_ID> --role compute.editor --service-account-id <sa_ID>

# Assign to user group
yc resource-manager folder add-access-binding \
  --id <folder_ID> --role viewer --subject group:<group_ID>

# List/revoke
yc resource-manager folder list-access-bindings --id <folder_ID>
yc resource-manager folder remove-access-binding \
  --id <folder_ID> --role editor --user-account-id <user_ID>
```

Subject formats: `userAccount:<id>`, `federatedUser:<id>`, `serviceAccount:<id>`, `group:<id>`, `system:allAuthenticatedUsers`, `system:allUsers`

---

## Compute

### VMs

```bash
# Create Linux VM
yc compute instance create \
  --name my-vm \
  --zone ru-central1-a \
  --network-interface subnet-name=default-a,nat-ip-version=ipv4 \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-22-04-lts,auto-delete=true \
  --ssh-key ~/.ssh/id_ed25519.pub

# Lifecycle
yc compute instance list
yc compute instance get <name_or_id>
yc compute instance start <name>
yc compute instance stop <name>       # graceful 30s, then force
yc compute instance restart <name>
yc compute instance delete <name>
yc compute instance update --name <name> --new-name <new>
```

Availability zones: `ru-central1-a`, `ru-central1-b`, `ru-central1-c`, `ru-central1-d`

VM statuses: PROVISIONING → STARTING → RUNNING → STOPPING → STOPPED. Also: CRASHED (auto-restart), ERROR (fatal).

### Preemptible VMs

25-70% cheaper, stopped after 24h or on resource shortage. No SLA.

```bash
yc compute instance create --name my-vm --preemptible ...
yc compute instance update --name <name> --preemptible       # convert to preemptible
yc compute instance update --name <name> --no-preemptible    # convert to regular
```

### Disks

| Type | ID | Notes |
|------|----|-------|
| Network SSD | `network-ssd` | Default, replicated |
| Network HDD | `network-hdd` | Cheaper, replicated |
| Non-replicated SSD | `network-ssd-nonreplicated` | High perf, size multiple of 93 GB |
| Ultra-fast SSD ×3 | `network-ssd-io-m3` | Best perf + redundancy |

```bash
yc compute disk create --name my-disk --size 100 --type network-ssd --zone ru-central1-a
yc compute disk list
yc compute instance attach-disk --instance-name <vm> --disk-name <disk>
yc compute instance detach-disk --instance-name <vm> --disk-name <disk>
yc compute disk delete --name <disk>
```

### Images & Snapshots

```bash
# Images
yc compute image create --name my-img --source-disk-id <disk_ID> --family my-images
yc compute image list
yc compute image delete --name <name>

# Snapshots
yc compute disk-snapshot create --name my-snap --disk-id <disk_ID>
yc compute disk-snapshot list
yc compute disk-snapshot delete --name <name>

# Scheduled snapshots
yc compute snapshot-schedule create --name my-sched \
  --disk-ids <id1>,<id2> --expression "0 2 * * *"
```

### Instance Groups

```bash
yc compute instance-group create --file specification.yaml
yc compute instance-group list
yc compute instance-group get <name>
yc compute instance-group set-size --name <name> --size 5
yc compute instance-group delete <name>
```

Scale policies: `fixed_scale` (manual size) or `auto_scale` (CPU/custom metrics).

---

## VPC (Virtual Private Cloud)

### Networks & Subnets

```bash
yc vpc network create --name my-net --description "Production"
yc vpc subnet create --name my-sub --zone ru-central1-a \
  --range 10.1.2.0/24 --network-name my-net
yc vpc network list
yc vpc subnet list
```

Private ranges (RFC 1918): `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`. CIDR `/16` to `/28`. First two IPs reserved (gateway `.1`, DNS `.2`).

### Security Groups

Default SG created per network (allows all traffic). Max 5 SGs per interface, 50 rules per SG.

```bash
yc vpc security-group update-rules <id> \
  --add-rule "direction=ingress,port=443,protocol=tcp,v4-cidrs=[10.0.0.0/24]"
yc vpc security-group list
yc vpc security-group get <name>
```

Protocols: TCP, UDP, ICMP, AH, ESP, GRE, ANY. Stateful (return traffic auto-allowed). TCP idle timeout: 180s.

Note: metadata (`169.254.169.254:80`) and DNS (subnet `.2`:53) need explicit egress rules.

### Public IPs

```bash
yc vpc address create --external-ipv4 zone=ru-central1-a --deletion-protection
yc vpc address list
```

**Dynamic**: assigned on start, released on stop. **Static**: persistent, kept across stop/restart.

### NAT Gateway

Provides internet access without public IPs on VMs.

```bash
yc vpc gateway create --name my-gw
yc vpc route-table create --name my-rt --network-name my-net \
  --route destination=0.0.0.0/0,gateway-id=<gw_id>
yc vpc subnet update <subnet> --route-table-name my-rt
```

### Routing

```bash
yc vpc route-table create --name <name> --network-name <net>
yc vpc route-table list
yc vpc subnet update <subnet> --route-table-name <name>
```

Route priority: static `0.0.0.0/0` > VM public IP > NAT gateway > Cloud Interconnect. Larger mask = higher priority.

### Key limits

| Resource | Limit |
|----------|-------|
| Networks per cloud | 2 |
| Subnets per cloud | 12 |
| Static public IPs | 2 |
| Security groups per cloud | 10 |
| Rules per SG | 50 |
| NAT gateways | 20 |

---

## Object Storage (S3)

### Buckets & Objects

```bash
yc storage bucket create --name my-bucket
yc storage bucket list
yc storage bucket get my-bucket
```

Bucket names globally unique. Object key max 1024 bytes. Max object size 5 TB.

### Storage Classes

| Class | ID (upload) | Access | Min billing |
|-------|-------------|--------|-------------|
| Standard | `STANDARD` | Frequent | — |
| Cold | `COLD` / `STANDARD_IA` | ~1/month | — |
| Ice | `ICE` / `GLACIER` | ~1/year | 12 months |

All classes: same SLA, ×3 replication. Lifecycle rules can transition to colder only.

### Versioning & Lifecycle

```bash
yc storage bucket versioning enable my-bucket
```

Lifecycle actions: transition storage class, delete objects/versions, abort multipart uploads. Processed daily at 00:00 UTC.

### Encryption

```bash
yc storage bucket encrypt --name my-bucket --kms-key-id <key_id>
```

Server-side via KMS (envelope encryption). Applies to new objects only.

### Pre-signed URLs

```bash
aws --endpoint-url=https://storage.yandexcloud.net \
  s3 presign s3://bucket/key --expires-in 3600
```

### S3 operations (AWS CLI)

```bash
# Upload/download
aws --endpoint-url=https://storage.yandexcloud.net s3 cp file.txt s3://bucket/key
aws --endpoint-url=https://storage.yandexcloud.net s3 cp s3://bucket/key file.txt
aws --endpoint-url=https://storage.yandexcloud.net s3 cp --recursive dir/ s3://bucket/prefix/

# List
aws --endpoint-url=https://storage.yandexcloud.net s3 ls s3://bucket/ --recursive
```

### Key limits

| Resource | Limit |
|----------|-------|
| Storage per cloud | 1,024 GB |
| Buckets per cloud | 25 |
| Max object size | 5 TB |
| Max request body | 5 GB |
| Max multipart parts | 10,000 |

---

## Container Registry

### Registry & Images

```bash
yc container registry create --name my-registry
yc container registry list
yc container image list --repository-name <registry_ID>/<image_name>
```

Image path: `cr.yandexcloud.net/<registry_ID>/<image_name>:<tag>`

### Docker authentication

**Credential Helper (recommended)**:
```bash
yc container registry configure-docker   # adds to ~/.docker/config.json
```

**OAuth/IAM token**:
```bash
echo <token> | docker login --username oauth --password-stdin cr.yandexcloud.net
echo <token> | docker login --username iam --password-stdin cr.yandexcloud.net
```

### Push/Pull

```bash
docker tag my-app:1.0 cr.yandexcloud.net/<registry_ID>/my-app:1.0
docker push cr.yandexcloud.net/<registry_ID>/my-app:1.0
docker pull cr.yandexcloud.net/<registry_ID>/my-app:1.0
```

### Lifecycle Policies

Per-repository. Filter by tag regex or `untagged: true`. Delete conditions: `expire_period` (age) and `retained_top` (keep N newest).

```bash
yc container image lifecycle-policy create \
  --repository-name <registry_ID>/<image> --rules-file lifecycle.json
yc container image lifecycle-policy dry-run <policy_ID>
yc container image lifecycle-policy update <policy_ID> --status active
```

### Vulnerability Scanning

```bash
yc container image scan <image_ID>
```

Supports 15+ OS distros and language packages (Ruby, Python, PHP, Node.js, .NET, Java, Go, Rust, Dart). Scan types: manual, on-push, scheduled.

### Key limits

| Resource | Limit |
|----------|-------|
| Registries per cloud | 10 |
| Max layer size | 150 GB |
| Max layers per image | 127 |
| Max scan size | 2 GB |

---

## Common yc Cheat Sheet

```bash
# Auth
yc init                                    # interactive setup
yc iam create-token                        # get IAM token

# Resources
yc compute instance list                   # list VMs
yc compute instance create --name <n> ...  # create VM
yc vpc network list                        # list networks
yc storage bucket list                     # list buckets

# Info
yc config list                             # current profile
yc resource-manager folder list            # list folders
yc resource-manager cloud list             # list clouds

# Operations
yc operation get <op_id>                   # check async op
yc operation wait <op_id>                  # wait for async op

# SSH
yc compute ssh --name <vm>                 # SSH into VM
```

See also: [yc-managed-db.md](yc-managed-db.md) for managed database services.
