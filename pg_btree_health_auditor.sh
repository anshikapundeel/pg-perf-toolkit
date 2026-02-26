#!/bin/bash
# ==============================================================================
# Script: pg_btree_health_auditor.sh
# Author: Anshika Pundeel
# Description: Connects to a PostgreSQL instance and runs a deep audit on 
#              B-Tree indexes to find unused indexes wasting memory, and 
#              highly fragmented (bloated) indexes destroying I/O performance.
# ==============================================================================

if [ -z "$1" ]; then
    echo "Usage: ./pg_btree_health_auditor.sh <database_url>"
    echo "Example: ./pg_btree_health_auditor.sh postgres://user:pass@localhost:5432/mydb"
    exit 1
fi

DB_URL=$1

echo "🔍 Initiating PostgreSQL B-Tree Index Health Audit..."
echo "------------------------------------------------------------------"

# 1. Identify Unused Indexes (Wasting RAM and slowing down writes)
echo -e "\n[1] Detecting Unused Indexes (Zero Scans but taking up space):"
psql "$DB_URL" -x -c "
SELECT
    schemaname || '.' || relname AS table_name,
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS index_size,
    idx_scan AS number_of_scans
FROM pg_stat_user_indexes ui
JOIN pg_index i ON ui.indexrelid = i.indexrelid
WHERE idx_scan = 0 
  AND indisunique IS FALSE
ORDER BY pg_relation_size(i.indexrelid) DESC
LIMIT 5;
"



# 2. Identify Missing Indexes (Sequential scans hitting large tables)
echo -e "\n[2] Detecting Missing Indexes (Tables with high Sequential Scans):"
psql "$DB_URL" -x -c "
SELECT
    relname AS table_name,
    seq_scan AS sequential_scans,
    idx_scan AS index_scans,
    seq_tup_read AS tuples_read_seq,
    pg_size_pretty(pg_table_size(relid)) AS table_size
FROM pg_stat_user_tables
WHERE seq_scan > 0 AND pg_table_size(relid) > 10000000 -- Larger than ~10MB
ORDER BY seq_tup_read DESC
LIMIT 5;
"

# 3. Cache Hit Ratio (Are indexes actually staying in memory?)
echo -e "\n[3] Global Index Cache Hit Ratio:"
psql "$DB_URL" -t -c "
SELECT 
    'Index Hit Ratio: ' || 
    ROUND((sum(idx_blks_hit) - sum(idx_blks_read)) / sum(idx_blks_hit + idx_blks_read) * 100, 2) || '%' 
FROM pg_statio_user_indexes;
"

echo "------------------------------------------------------------------"
echo "🎯 DIAGNOSTIC INSIGHTS:"
echo "- Unused Indexes: Drop these. Every INSERT/UPDATE pays a penalty maintaining them."
echo "- Missing Indexes: If a large table has massive sequential scans, it needs a B-Tree or Hash index."
echo "- Cache Hit Ratio: Should be > 95% for OLTP workloads. If lower, you need more RAM or to aggressively REINDEX bloated B-Trees."
echo "=================================================================="
