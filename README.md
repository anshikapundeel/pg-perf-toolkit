# PostgreSQL Performance Toolkit (`pg-perf-toolkit`)

A collection of advanced, production-grade diagnostic scripts designed to audit and troubleshoot PostgreSQL database bottlenecks. 

These tools go beyond basic CPU/RAM monitoring by querying internal PostgreSQL statistics catalogs (`pg_stat_*`) to uncover hidden performance killers like B-Tree index bloat, connection pool exhaustion, and poor cache hit ratios.

## 🛠️ Tools Included

### 1. `pg_btree_health_auditor.sh` (Index Bloat & Cache Analyzer)
**The Problem:** Due to PostgreSQL's Multi-Version Concurrency Control (MVCC), heavy `UPDATE` and `DELETE` workloads leave behind dead tuples. This heavily fragments and bloats B-Tree indexes, destroying memory cache hit ratios and driving up expensive disk I/O. Furthermore, applications often create indexes that are never used, wasting RAM and slowing down every `INSERT`.

**The Solution:** This tool connects directly to the DB and audits the internal statistics catalogs to identify:
1. Zero-scan (unused) indexes that should be dropped.
2. Missing indexes (large tables suffering from massive sequential scans).
3. The global index cache hit ratio to determine if RAM is properly sized.

**Usage:**
```bash
chmod +x pg_btree_health_auditor.sh
./pg_btree_health_auditor.sh postgres://user:password@localhost:5432/your_database

anshikapundeel.github.io
