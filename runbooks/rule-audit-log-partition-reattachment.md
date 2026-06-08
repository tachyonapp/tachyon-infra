# Runbook: Reattach a Detached `rule_audit_log` Partition

**SLA:** 4 business hours from request to partition reattached and queryable  
**Audience:** On-call engineer, compliance officer

---

## Background

`rule_audit_log` is a range-partitioned PostgreSQL table. Monthly partitions are detached after 24 months (moved out of the hot query path) and dropped after 5 years (GDPR/CCPA compliance). Detached partitions remain in the database as standalone tables — they are not deleted and can be reattached at any time.

A partition may need to be reattached for:
- Regulatory examination or subpoena
- Customer dispute investigation
- Internal compliance audit

---

## Step 1 — Identify the Partition

Determine the month of interest (YYYY-MM). The partition table name follows the pattern:

```
rule_audit_log_YYYY_MM
```

Example: audit records from March 2027 → `rule_audit_log_2027_03`

### Verify the partition exists and is detached

Connect to the production database and run:

```sql
-- Check if the partition table exists
SELECT relname, relkind
FROM pg_class
WHERE relname = 'rule_audit_log_YYYY_MM';

-- Confirm it is NOT currently attached (no row = detached)
SELECT child.relname
FROM pg_inherits i
JOIN pg_class child  ON i.inhrelid  = child.oid
JOIN pg_class parent ON i.inhparent = parent.oid
WHERE parent.relname = 'rule_audit_log'
  AND child.relname  = 'rule_audit_log_YYYY_MM';
```

If the first query returns no row, the partition has already been **dropped** (5-year window expired). Dropped partitions cannot be recovered from the live database — consult the cold-storage archival process if a pg_dump backup was taken before the drop.

If the second query returns no row, the partition is detached and can be reattached.

---

## Step 2 — Reattach the Partition

Run the following command. Replace `YYYY_MM` and the date bounds with the correct values for the target month.

```sql
-- Example: reattaching March 2027
ALTER TABLE rule_audit_log
  ATTACH PARTITION rule_audit_log_2027_03
  FOR VALUES FROM ('2027-03-01') TO ('2027-04-01');
```

**Date bounds formula:** `FROM ('YYYY-MM-01') TO ('YYYY-MM+1-01')` where `MM+1` is the next calendar month (handle year rollover for December).

This operation acquires a brief lock on the parent table. It completes in seconds on detached partitions — the partition data is already on disk.

---

## Step 3 — Verify Rows Are Queryable

```sql
-- Confirm rows are visible via the parent table
SELECT COUNT(*) FROM rule_audit_log
WHERE evaluated_at >= '2027-03-01'
  AND evaluated_at  < '2027-04-01';

-- Optionally query the partition directly
SELECT COUNT(*) FROM rule_audit_log_2027_03;
```

Both counts should match.

---

## Step 4 — Scope the Examination Query

Use the existing indexes for efficient access:

```sql
-- By bot
SELECT * FROM rule_audit_log
WHERE bot_id = <bot_id>
  AND evaluated_at >= '2027-03-01'
  AND evaluated_at  < '2027-04-01'
ORDER BY evaluated_at DESC;

-- By user
SELECT * FROM rule_audit_log
WHERE user_id = <user_id>
  AND evaluated_at >= '2027-03-01'
  AND evaluated_at  < '2027-04-01'
ORDER BY evaluated_at DESC;

-- Failed evaluations only
SELECT * FROM rule_audit_log
WHERE passed = false
  AND evaluated_at >= '2027-03-01'
  AND evaluated_at  < '2027-04-01'
ORDER BY evaluated_at DESC;
```

---

## Step 5 — Detach After Examination

Once the examination is complete, detach the partition again to keep the hot table lean. Run this **outside a transaction block**:

```sql
ALTER TABLE rule_audit_log
  DETACH PARTITION rule_audit_log_2027_03 CONCURRENTLY;
```

`CONCURRENTLY` avoids locking out live queries on `rule_audit_log` during the detach. It may take a few seconds to complete.

---

## Step 6 — Confirm Detach

```sql
-- Should return no row after detach
SELECT child.relname
FROM pg_inherits i
JOIN pg_class child  ON i.inhrelid  = child.oid
JOIN pg_class parent ON i.inhparent = parent.oid
WHERE parent.relname = 'rule_audit_log'
  AND child.relname  = 'rule_audit_log_2027_03';
```

---

## Notes

- **The `tachyon_app` database role has `DELETE` revoked on all `rule_audit_log` partitions.** This is enforced at the partition level. Audit records cannot be deleted by the application — this is a compliance control. Only a superuser can delete records from this table.
- **Reattaching does not restore the `REVOKE DELETE` grant.** When `ATTACH PARTITION` is called, the partition inherits the parent's row-level security but partition-level privilege revocations must be re-applied manually if needed:
  ```sql
  REVOKE DELETE ON rule_audit_log_YYYY_MM FROM tachyon_app;
  ```
- **Do not drop the partition during examination.** The `audit-log-partition` cron only drops partitions that exceed the 5-year retention window. Manual drops outside this window are a compliance violation.
