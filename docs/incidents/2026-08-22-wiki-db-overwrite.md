# Incident Report: Production Wiki Database Overwritten by Stale Sync Cron

**Date:** 2026-08-22 (detected/resolved) · **Reported:** 2026-08-25
**Severity:** High (production data loss) · **Status:** Resolved, prevention tracked below
**Services impacted:** wiki (wiki.wetfish.net), production k3s cluster (216.128.155.242)

## Summary

Between **Aug 17 06:00 UTC and Aug 22 ~08:00 UTC**, an hourly cron job on the
production k3s host continuously overwrote the production wiki database
(`wikidb`) with a frozen snapshot of the **old** production database from
149.28.239.165. Any wiki edits made after the Aug 17 DNS cutover were silently
destroyed roughly every hour until the job was disabled. Pages had to be
manually restored from backups.

## Timeline (UTC)

| Time | Event |
|---|---|
| pre-Aug 17 | `/opt/sync-from-vultr.sh` + hourly root cron created on k3s host to mirror old-prod → k3s ahead of migration |
| Aug 17 06:00 | First logged sync run; DNS cutover sends live traffic to k3s. **Cron left enabled** |
| Aug 17–22, hourly ×123 | Each run: `mysqldump` from old-prod piped into prod `wikidb` (dump includes `DROP TABLE IF EXISTS` → full overwrite), plus uploads rsync |
| Aug 17–22 | Wiki edits made by users during this window repeatedly reverted to pre-cutover state |
| ~Aug 21–22 | Data loss noticed; restore from backup performed (`wiki-mysql` pod logged 24 restarts during restore churn) |
| Aug 22 ~08:00 | Root crontab entry commented out: `# DISABLED 2026-08-22 data-loss incident`; last sync log entries ~08:00Z |
| Aug 25 | Post-incident hardening: script refuses post-cutover runs without explicit opt-in flag (deployed to `/opt` + merged); forensic snapshot taken |

## Root Cause

A **direction-dependent, destructive migration tool was scheduled as an
unattended recurring job with no expiry, guard, or post-cutover kill switch**.

`sync-from-vultr.sh` exists solely to copy data *from* the legacy Docker prod
host *into* k3s — valid only before cutover. Once cutover happened:

1. old-prod froze (no longer receiving writes), so every sync pushed stale
   data backward in time onto production;
2. `mysqldump` output includes `DROP TABLE IF EXISTS`, so each import fully
   replaced all 7 `wikidb` tables;
3. the cron ran as root with no ownership/alerting tie-in, so nobody was
   notified of the ongoing overwrite.

Contributing factors:
- Migration runbook had no explicit step *"disable old-direction sync crons at
  cutover"*
- No monitoring alert on wiki row-count regressions
- The uploads rsync half was benign only because rsync without `--delete`
  is additive

## Detection & Response

Detected manually via visibly reverting/stale wiki content. Response:

1. Disabled the cron entry (root crontab, Aug 22)
2. Restored affected pages from existing backups
3. Verified DB state post-restore

Detection latency (~5 days) was the biggest gap — automated alerting would
have caught the first overwrite within an hour.

## Evidence

- Full sync-job log preserved: [`wiki-sync-evidence.txt`](./wiki-sync-evidence.txt)
  (123 × "Starting wiki DB sync" runs)
- Forensic DB snapshot: `vultr-s3:wetfish-backups/incident-snapshots/2026-08-25T020400Z/`
  (`wikidb.sql.gz` + SHA256 + `backups.log`)
- Crontab comment retained: `# DISABLED 2026-08-22 data-loss incident`
- Guarded script: repo `scripts/sync-from-vultr.sh` (FishStack-k3d PR #6) and
  deployed copy at `/opt/sync-from-vultr.sh` (pre-guard backup:
  `/opt/sync-from-vultr.sh.bak-20260825`)

## What Went Well

- Regular 6-hourly S3 backups (`backup-k3s.sh`) were unaffected and enabled restore
- Uploads rsync was non-destructive (additive), so uploaded files were never lost
- Cron was disabled with a self-documenting comment preserving the why

## Action Items

| # | Action | Status |
|---|---|---|
| 1 | Disable destructive post-cutover crons at cutover time | ✅ Done (Aug 22, late) |
| 2 | Hard-guard `sync-from-vultr.sh` behind `--force-post-cutover` | ✅ Done (PR #6 + deployed) |
| 3 | Forensic snapshot of wikidb + logs to S3 | ✅ Done (`incident-snapshots/2026-08-25T020400Z`) |
| 4 | Preserve sync log in repo | ✅ Done (`docs/incidents/wiki-sync-evidence.txt`) |
| 5 | Alert on sudden drop in `wikidb.Wiki_Pages` row count (mysqld-exporter rule) | ⬜ TODO |
| 6 | Enable S3 object-lock/versioning on `wetfish-backups` | ⬜ TODO |
| 7 | Add runbook step: inventory + kill all migration-direction crons as explicit cutover gate | ⬜ TODO |
| 8 | Quarterly restore drill from `wetfish-backups` | ⬜ TODO |
| 9 | Audit remaining crons on k3s host + old-prod for direction hazards | ⬜ TODO |

## Lessons Learned

1. **Every migration script needs an expiration date.** One-way sync jobs are
   bombs after cutover; require an explicit override flag that names the risk.
2. **Cutover runbooks need a cron-kill checklist**, not just DNS flips.
3. **Data-integrity alerting beats backups** for detection speed — row-count
   deltas are cheap to monitor.
4. **Log retention saved the investigation**: `/var/log/wiki-sync.log` gave an
   exact, auditable timeline (123 overwrites) without guesswork.
