# Production Consolidation Roadmap

> Move all wetfish services old-prod → new-prod (k3s), repurpose old-prod as k3s staging, wipe `144.202.63.236`.
> **Safety rule: no data is removed at any step without explicit approval. All operations are additive dumps/syncs unless a "destroy" gate is explicitly called out.**

## Servers

| Role | IP | Platform | Notes |
|---|---|---|---|
| new prod | `216.128.155.242` | k3s (single node) | forum live; other 5 deployed, DBs empty |
| old prod | `149.28.239.165` | Docker Compose | all services + real data; → new staging |
| staging/mini-forum | `144.202.63.236` | Docker Compose | testforum; also SSH jump → k3s; → wipe |

## Decisions

- New staging = k3s (mirror prod)
- DNS cutover = manual (Cloudflare)
- Wipe target = `144.202.63.236` (single box)
- Cutover = rolling, per-service
- Cert strategy = repo `http01` issuer (no token needed); alt: dns01 + `wetfish.net` token for pre-issue
- Target state already encoded in `services/*/k8s/overlays/prod` — reconcile live→git, don't author new config

## Phase 0 — Pre-flight (non-destructive)

- [ ] Resolve cert-issuer strategy (http01 default)
- [ ] `preflight-prod.sh` — GHCR `prod-*` images present, PVC vs data sizing, SSH reachability, drift inventory (live vs git)
- [ ] `snapshot-dbs.sh` — dump all old-prod DBs to S3 as a named restore point
- [ ] Add SSH key to k3s for direct access (removes jump dependency)
- [ ] Confirm 5 Cloudflare records to change (user)

## Phase 1 — Reconcile live → git

- [ ] `kubectl apply -k` current prod overlays for all 5 services — adds missing `cert-manager.io/cluster-issuer` annotations (live ingresses lack them; no `Certificate` objects exist yet)
- [ ] Reconcile ClusterIssuer to P0 decision (repo `http01` vs live `dns01`)
- [ ] Decide: add forum to `clusters/prod/apps` (GitOps) or keep manual; commit live `wetfishonline.com` hosts to git

## Phase 2 — Bulk data prep (automated, zero downtime)

- [ ] `migrate-service.sh wiki` — dump `wiki` → import `wikidb`; rsync uploads → `wiki-uploads-pvc`
- [ ] `migrate-service.sh click` — dump `click` → `clickdb`
- [ ] `migrate-service.sh danger` — dump `fishy` → `dangerdb`
- [ ] home/glitch: no data (code already in images)

## Phase 3 — Rolling cutover (wiki → click → danger → home → glitch)

Per service:
1. User cuts DNS → `216.128.155.242`
2. `wait-cert.sh` polls until `<svc>-tls` READY
3. `validate-prod.sh <svc>` — HTTPS + DB checks
4. Soak via FishVision/Uptime-Kuma → next

Rollback: re-point DNS; old-prod still running.

## Phase 4 — Decommission old-prod services

- [ ] Soak 1–2 weeks
- [ ] Stop wiki/home/glitch/click/danger/online containers (keep data dirs — no deletion)

## Phase 5 — Build k3s staging on old-prod

- [ ] `install-k3s-staging.sh` → `deploy.sh --env staging` → `bootstrap-flux.sh staging` → restore staging data
- [ ] User wires `staging-<svc>.wetfish.net` DNS

## Phase 6 — Wipe staging/mini-forum (`144.202.63.236`)

- [ ] Gate: direct SSH (P0) + staging functional (P5)
- [ ] **Destroy gate:** retire testforum data, remove DNS, wipe box — *requires explicit approval*

---

## S3 Backup Plan (new prod)

### Current prod reference (works, runs every 6h on `149.28.239.165`)

- `util/improved-backups.sh` via cron: dumps allowlisted DBs (wiki/online/click/danger) from `docker exec`, uploads to `vultr-s3:wetfish-backups/databases/<date>/`, syncs wiki uploads to `vultr-s3:wetfish-uploads`
- Transport: `rclone` v1.71, remote `vultr-s3` → `ewr1.vultrobjects.com`, buckets `wetfish-backups` + `wetfish-uploads`
- DB name mapping on old prod: `wiki`, `forums` (online), `click`, `fishy` (danger)
- Wiki uploads in S3: **19.5 GiB / 38k objects**

### New prod design (runs on k3s, every 6h)

`backup-k3s.sh` (cron on `216.128.155.242`):
1. Dump 4 DBs via `kubectl exec` → `vultr-s3:wetfish-backups/databases/<date>/` (+ `.sha256`)
   - `wikidb`, `clickdb`, `dangerdb`, `forumdb` (passwords read from k8s secrets)
2. `rclone sync` wiki uploads PVC hostPath → `vultr-s3:wetfish-uploads`
3. `rclone sync` forum `appdata` + `wwwroot` PVCs → `vultr-s3:wetfish-backups/forum-files/`
4. Prune local staging (7d); S3 keeps full history
5. Write node_exporter textfile metric (once exporter is added)

### Setup steps (additive)

- Install `rclone` on k3s
- Deploy `rclone.conf` with `vultr-s3` remote (creds live on the server, never committed)
- Install cron entry
- **Verify** with a spot-check restore (dump + re-import a single table into a scratch DB)

### Open items

- Forum appdata/wwwroot currently backed by nothing on old prod — new coverage.
- Wiki uploads 19.5 GiB vs `wiki-uploads-pvc` 25 GiB — resize PVC before Phase 2 rsync.
