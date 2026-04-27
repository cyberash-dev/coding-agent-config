# Yandex Cloud Managed Database Services

## Common Concepts

### Cluster Architecture

**Cluster → Hosts → Databases**

- **Cluster**: Group of database hosts (VMs with DBMS), managed as single entity
- **Hosts**: Reside in different availability zones for fault tolerance
- **Replication**: Automatic (sync/async depending on service)

### Host Classes (tiers)

| Tier | Type | vCPU guarantee | Examples |
|------|------|----------------|----------|
| `b1`/`b2`/`b3` | Burstable | 50% | b2.medium: 2 vCPU, 4 GB |
| `s1`/`s2`/`s3`/`s4` | Standard | 100% | s2.micro: 2/8 → s2.6xlarge: 64/256 |
| `m2`/`m3`/`m4` | Memory-optimized | 100% | m2.nano: 1/8 → m2.8xlarge: 64/512 |
| `c3`/`c4` | Compute-optimized | 100% | c3-c2-m4: 2/4 → c3-c64-m128: 64/128 |
| `s4a`/`c4a`/`m4a` | AMD Zen 4 | 100% | Up to 256 vCPU, 1024 GB |

### Storage Types

| Type | ID | Notes |
|------|----|-------|
| Network SSD | `network-ssd` | Replicated, recommended default |
| Network HDD | `network-hdd` | Cheaper, replicated |
| Local SSD | `local-ssd` | Highest perf, requires 3+ hosts |
| Non-replicated SSD | `network-ssd-nonreplicated` | High perf, requires 3+ hosts |
| Ultra-fast SSD ×3 | `network-ssd-io-m3` | Best perf + redundancy |

Storage range: 10 GB → 10,230 GB (standard); up to 16,368 GB (AMD Zen 4).

### Availability & Maintenance

- **Non-HA**: Single host (no SLA)
- **HA**: 2+ hosts in different AZs (SLA applies)
- **Production HA**: 3+ hosts across 3 AZs
- **Maintenance window**: Configurable, quorum-based updates
- **Backups**: Automatic daily + manual on-demand, retention 3-60 days
- **Read-only mode**: Triggered at 97%+ storage capacity

---

## Managed PostgreSQL

### Architecture

- Master + replicas with **quorum-based synchronous replication** (WAL streaming)
- Quorum = floor(N/2) for N replicas; min 1 for single replica
- `synchronous_commit`: `on` (default — writes to master + quorum disk), `remote_apply` (read consistency)
- Manual failover supported with cascade replication option

### Connection Pooling (Odyssey)

Built-in connection pooler, no extra infrastructure needed.

| Mode | Description | Limitations |
|------|-------------|-------------|
| **Session** (default) | Connection per client session | None — supports all PG features |
| **Transaction** | Connection returned after tx | No temp tables, cursors, advisory locks |
| **Query** | Single query per connection | Best with AUTOCOMMIT only |

### Storage & Backups

- **Auto-expansion**: Two thresholds — scheduled (maintenance) + immediate
- **Read-only**: Triggered at 97% capacity, recovery via storage increase or manual disable
- **Backups**: Daily automatic (7-day default retention), manual (unlimited), point-in-time recovery
- **Logical decoding**: `test_decoding`, `wal2json`, `pgoutput` plugins for CDC

### Key Commands

```bash
# Cluster management
yc managed-postgresql cluster create <name> \
  --environment production --version 16 \
  --resource-preset s2.micro --disk-size 20 --disk-type network-ssd \
  --host zone-id=ru-central1-a,subnet-id=<id> \
  --host zone-id=ru-central1-b,subnet-id=<id> \
  --network-name <net> \
  --database name=mydb,owner=myuser \
  --user name=myuser,password=<pass>

yc managed-postgresql cluster list
yc managed-postgresql cluster get <name_or_id>
yc managed-postgresql cluster list-operations <id>
yc managed-postgresql cluster update <name> ...
yc managed-postgresql cluster delete <name>

# Hosts
yc managed-postgresql hosts list --cluster-name <name>
yc managed-postgresql hosts add --cluster-name <name> --host zone-id=ru-central1-c,subnet-id=<id>

# Databases & users
yc managed-postgresql database list --cluster-name <name>
yc managed-postgresql user list --cluster-name <name>
```

---

## Managed ClickHouse

### Architecture

- Multiple hosts organized into **shards** and **replicas**
- No dedicated master per shard — all replicas are equal
- **Distributed tables** route queries across shards using a sharding key
- Shard groups: organize shards for selective query routing

### Coordination

| Option | Hosts | Notes |
|--------|-------|-------|
| **ClickHouse Keeper (embedded)** | 3+ CH hosts | Default, no extra hosts |
| **ClickHouse Keeper (separate)** | 3 or 5 dedicated CK hosts | For large clusters |
| **ZooKeeper (legacy)** | 3 or 5 ZK hosts | Older clusters |

### Replication

- Engine: **ReplicatedMergeTree** for automatic replication
- Replicated DB supports metadata replication across hosts
- Usage: `CREATE TABLE db.tbl ON CLUSTER '{cluster}' ENGINE = ReplicatedMergeTree(...)`

### Hybrid Storage

- Hot data in cluster storage, cold (TTL-expired) in Object Storage
- Policies: `default` (auto-manage), `local` (cluster only), `object_storage` (S3 only)
- Supported engines: MergeTree family only

### Backups

- Automatic daily (configurable window, default 22:00-23:00 UTC)
- Incremental (dedup within 30 days), retention 3-60 days (default 30)
- Manual backups: unlimited retention
- Includes all MergeTree tables; other engines = schemas only

### Key Commands

```bash
yc managed-clickhouse cluster create <name> \
  --environment production \
  --clickhouse-resource-preset s2.medium \
  --host type=clickhouse,zone-id=ru-central1-a,subnet-id=<id> \
  --host type=clickhouse,zone-id=ru-central1-b,subnet-id=<id> \
  --host type=clickhouse,zone-id=ru-central1-c,subnet-id=<id> \
  --network-name <net> \
  --database name=mydb \
  --user name=myuser,password=<pass>

yc managed-clickhouse cluster list
yc managed-clickhouse cluster get <name_or_id>
yc managed-clickhouse cluster list-operations <id>
yc managed-clickhouse version list

# Shards
yc managed-clickhouse shards list --cluster-name <name>
yc managed-clickhouse shards add --cluster-name <name> --name shard2 \
  --host zone-id=ru-central1-a,subnet-id=<id>
```

---

## Managed Kafka

### Architecture

- **Brokers**: Store topic partitions, accept producer/consumer connections
- **Topics**: Message stream categories containing partitions
- **Partitions**: Ordered message sequences, replicated across brokers
- **Leader broker**: Accepts reads/writes per partition; followers replicate

### Coordination

| Mode | Kafka version | Notes |
|------|---------------|-------|
| **ZooKeeper** | ≤3.9 | 1 broker = ZK on same host; 2+ = 3 separate ZK hosts (auto) |
| **KRaft combined** | ≥3.6 | Brokers + metadata on same hosts (not for critical envs) |
| **KRaft split** | ≥3.6 | 3 dedicated metadata controller hosts |

ZK hosts auto-created and cannot be deleted. KRaft requires exactly 3 brokers.

### Key Concepts

- **Replication factor**: Number of copies (RF=2 → 1 leader + 1 follower)
- **min.insync.replicas**: Minimum ISR before writes are rejected
- **Service topics** (read-only): `__schema_registry`, `__connect-configs`, `__connect-offsets`, `__connect-status`
- **Connectors**: Source/sink connectors for external system integration
- **Schema Registry**: Built-in schema management

### Key Commands

```bash
yc managed-kafka cluster create <name> \
  --environment production \
  --kafka-resource-preset s2.medium \
  --brokers-count 3 \
  --host zone-id=ru-central1-a,subnet-id=<id> \
  --host zone-id=ru-central1-b,subnet-id=<id> \
  --host zone-id=ru-central1-c,subnet-id=<id> \
  --network-name <net>

yc managed-kafka cluster list
yc managed-kafka cluster get <name_or_id>
yc managed-kafka cluster list-operations <id>

# Topics
yc managed-kafka topic list --cluster-name <name>
yc managed-kafka topic create --cluster-name <name> \
  --name my-topic --partitions 6 --replication-factor 3

# Users
yc managed-kafka user list --cluster-name <name>
```

---

## Managed Valkey (Redis)

### Architecture

- **Master-replica**: Asynchronous replication from master to replicas
- **Sharded**: 1-10 shards (Valkey Cluster mode), 16,384 hash slots
- **Memory**: `maxmemory` = 75% of available RAM
- **Failover agent**: rdsync (Yandex status management) handles master promotion
- **Priority-based master selection**: Highest priority wins, tie-break by replication lag

### Persistence Options

| Mode | Config | Notes |
|------|--------|-------|
| **AOF** (default) | `appendonly yes`, RDB preamble | Every write logged, rewrite at 100%/64MB |
| **Disabled** | `appendonly no`, `save ""` | Pure in-memory |
| **Replicas-only** | Master disabled, replicas keep AOF | Faster master writes |

### Sharding (Valkey Cluster)

- 16,384 hash slots distributed across shards
- Failover: majority of masters detect failure → replica promoted
- Rebalancing: add shards without downtime
- Scalability: 1-10 shards
- Fault tolerance: even-host configs OR 2+ shards

### Key Commands

```bash
yc managed-valkey cluster create <name> \
  --environment production \
  --valkey-resource-preset m3.medium \
  --disk-type network-ssd --disk-size 16 \
  --host zone-id=ru-central1-a,subnet-id=<id> \
  --host zone-id=ru-central1-b,subnet-id=<id> \
  --host zone-id=ru-central1-c,subnet-id=<id> \
  --network-name <net>

yc managed-valkey cluster list
yc managed-valkey cluster get <name_or_id>

# Also available as legacy alias:
yc managed-redis cluster list
```

---

## YDB

### Architecture

- Distributed OLTP/OLAP database with separate compute and storage layers
- **Tablets**: Consistent distributed state machines (unit of processing)
- **Storage layer**: 3-fold replication across AZs in storage groups (9 total: 3 disks × 3 AZs)
- **Compute layer**: Tablets + YQL query executor

### Deployment Modes

| Mode | Resources | Pricing | Best for |
|------|-----------|---------|----------|
| **Serverless** | Auto-allocated | Per-query (RU) + per-GB storage | Variable workloads, dev/test |
| **Dedicated** | Explicit VMs (slots) | Per-hour + storage | Predictable workloads, production |

### Serverless Mode

- **Request Units (RU)**: Metric combining CPU, I/O, memory
- **Throttling**: Max RU/s cap (default 10, adjustable)
- **Burst**: ~5 min × 60s × limit of accumulated unused RUs
- **Data limit**: Default 50 GB (adjustable)
- Error on limit: `Throughput limit exceeded`

### Dedicated Mode — Configurations

| Preset | vCPU | RAM |
|--------|------|-----|
| `medium` | 8 | 32 GB |
| `medium-m64` | 8 | 64 GB |
| `medium-m96` | 8 | 96 GB |
| `large` | 12 | 48 GB |
| `xlarge` | 16 | 64 GB |
| `olap-c16-m128` | 16 | 128 GB (OLAP) |
| `oltp-c16-m128` | 16 | 128 GB (OLTP) |

Minimum production: 3 slots for reliability.

### Key Features

- **YQL**: SQL-like query language
- **Document API**: DynamoDB-compatible API
- **CDC** (Change Data Capture): Stream changes to external systems
- **TTL**: Automatic row expiration
- **OLAP**: Column-oriented storage for analytics (spills to disk if RAM insufficient)
- **Backups**: Daily automatic + manual on-demand

### Key Commands

```bash
# Create serverless
yc ydb database create <name> --serverless

# Create dedicated
yc ydb database create <name> \
  --resource-preset medium \
  --storage-type ssd \
  --storage-size 100 \
  --network-name <net> \
  --subnet-id <id> --subnet-id <id2> --subnet-id <id3>

# Management
yc ydb database list
yc ydb database get <name>
yc ydb database update <name> --throttling-rcu 100          # serverless: set RU limit
yc ydb database update <name> --storage-size-limit 100      # serverless: set data limit
yc ydb database delete <name>

# Backups
yc ydb backup list --database-id <id>
```

---

## Comparison Table

| Service | Best for | Scaling | HA minimum | Replication | Sharding |
|---------|----------|---------|------------|-------------|----------|
| **PostgreSQL** | OLTP, relational | Vertical (host class) | 2 hosts, 2 AZs | Quorum-sync (WAL) | No (single master) |
| **ClickHouse** | OLAP, analytics | Horizontal (shards) | 3 hosts, 3 AZs | ReplicatedMergeTree | Yes (distributed tables) |
| **Kafka** | Event streaming | Horizontal (brokers) | 3 brokers, 3 AZs | Partition replication | Yes (topic partitions) |
| **Valkey** | Cache, key-value | Horizontal (shards) | 3 hosts, 3 AZs | Async master-replica | Yes (16K hash slots) |
| **YDB** | Distributed OLTP/OLAP | Auto (serverless) / vertical+horizontal (dedicated) | 3 slots, 3 AZs | Consensus (tablets) | Auto (tablet splitting) |

---

## Common CLI Patterns

```bash
# All services follow similar patterns:
yc managed-<service> cluster create <name> ...
yc managed-<service> cluster list
yc managed-<service> cluster get <name_or_id>
yc managed-<service> cluster update <name> ...
yc managed-<service> cluster delete <name>
yc managed-<service> cluster list-operations <id>
yc managed-<service> hosts list --cluster-name <name>

# Exception: YDB uses different command group
yc ydb database create/list/get/update/delete
```

See also: [yc-reference.md](yc-reference.md) for yc CLI, IAM, Compute, VPC, S3, Container Registry.
