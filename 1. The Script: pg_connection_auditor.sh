#!/bin/bash
# ==============================================================================
# Script: pg_connection_auditor.sh
# Author: Anshika Pundeel
# Description: Advanced connection pool and transaction state auditor.
#              Detects connection leaks, "idle in transaction" lock-holders, 
#              and connection exhaustion risks in PostgreSQL.
# ==============================================================================

if [ -z "$1" ]; then
    echo "Usage: ./pg_connection_auditor.sh <database_url>"
    echo "Example: ./pg_connection_auditor.sh postgres://user:pass@localhost:5432/mydb"
    exit 1
fi

DB_URL=$1

echo "🔌 Initiating PostgreSQL Connection Pool & State Audit..."
echo "------------------------------------------------------------------"

# 1. Connection Saturation (Are we about to hit max_connections?)
echo -e "\n[1] Global Connection Pool Saturation:"
psql "$DB_URL" -t -c "
WITH conn_stats AS (
  SELECT count(*) AS current_conns, 
         current_setting('max_connections')::int AS max_conns
  FROM pg_stat_activity
)
SELECT 
  current_conns || ' / ' || max_conns || ' (' || 
  ROUND((current_conns::numeric / max_conns) * 100, 2) || '% utilized)'
FROM conn_stats;
"

# 2. Connection State Analysis (Hunting for Leaks & Zombies)
echo -e "\n[2] Connection Distribution by State:"
psql "$DB_URL" -c "
SELECT 
    state, 
    count(*) AS connection_count,
    ROUND((count(*)::numeric / (SELECT count(*) FROM pg_stat_activity)) * 100, 2) AS percentage
FROM pg_stat_activity 
WHERE state IS NOT NULL
GROUP BY state 
ORDER BY connection_count DESC;
"

# 3. The "Silent Killer" - Idle in Transaction Analysis
echo -e "\n[3] 'Idle in Transaction' Violators (Holding locks & blocking Autovacuum):"
psql "$DB_URL" -x -c "
SELECT 
    pid, 
    usename AS user, 
    application_name, 
    client_addr AS ip_address,
    now() - state_change AS duration_idle,
    query AS last_query_executed
FROM pg_stat_activity 
WHERE state = 'idle in transaction'
  AND now() - state_change > interval '10 seconds'
ORDER BY duration_idle DESC
LIMIT 3;
"

# 4. Long-Running Active Queries (Blocking the pool)
echo -e "\n[4] Longest Running Active Queries (Over 30 seconds):"
psql "$DB_URL" -x -c "
SELECT 
    pid,
    application_name,
    now() - query_start AS running_duration,
    query
FROM pg_stat_activity
WHERE state = 'active' 
  AND now() - query_start > interval '30 seconds'
ORDER BY running_duration DESC
LIMIT 3;
"

echo "------------------------------------------------------------------"
echo "🎯 DIAGNOSTIC INSIGHTS:"
echo "- High 'idle' count: The application is keeping connections open but doing nothing. You need a connection pooler like PgBouncer."
echo "- 'idle in transaction' > 0: Critical issue. The app started a transaction (BEGIN) but never committed or rolled back. This blocks vacuuming and causes table bloat."
echo "- High saturation (> 80%): Risk of 'FATAL: sorry, too many clients already'. Scale max_connections or implement multiplexing."
echo "=================================================================="
