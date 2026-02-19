# DevSecOps Security & Infrastructure Audit

**Project:** Wetfish Web Services - Kubernetes Migration
**Audit Date:** 2026-02-12
**Scope:** Full-stack review - application code, container images, Kubernetes manifests, CI/CD pipelines, infrastructure configuration
**Methodology:** Manual SAST, configuration review, OWASP Top 10 (2021) mapping, CIS Kubernetes Benchmark alignment
**Classification:** Internal - Action Items & Remediation Tracker

---

## Executive Summary

This audit covers the wetfish wiki service deployed on k3d (k3s-in-Docker) as part of the Docker Compose to Kubernetes migration. The legacy PHP application carries significant inherited technical debt, particularly around input validation and authentication. The infrastructure layer (Kubernetes manifests, container images, CI/CD) has foundational gaps typical of early-stage migrations that must be addressed before production readiness.

**Finding Severity Distribution:**

| Severity | Count | SLA Target |
|----------|-------|------------|
| Critical | 6 | Immediate / pre-production gate |
| High | 6 | 30 days |
| Medium | 10 | 90 days |
| Low | 8 | Best effort / next sprint |

---

## Critical Findings (P0)

### CRIT-01: Pervasive SQL Injection - OWASP A03:2021 (Injection)

**CWE:** CWE-89 (SQL Injection)
**CVSS 3.1:** 9.8 (Critical)
**Affected Files:**
- `services/wiki/wwwroot/index.php` (lines 138, 198, 230, 270, 300-330)
- `services/wiki/wwwroot/functions.php` (`RandomRow()`, `user_banned()`)
- `services/wiki/wwwroot/ban.php` (ban/revert queries)
- `services/wiki/wwwroot/gallery.php`
- `services/wiki/wwwroot/fun/*.php`

**Description:**
The application constructs SQL queries via direct string interpolation of user-controlled input. The `Clean()` function in `functions.php` performs HTML entity encoding only (`htmlspecialchars`), which provides zero protection against SQL injection. Every database-touching endpoint is vulnerable.

```php
// index.php:138 - Direct interpolation of $userIP into INSERT
mysqli_query($mysql,"INSERT INTO 'Wiki_Accounts' VALUES ('NULL', '$userIP', ...)");

// functions.php - Clean() is NOT SQL sanitization
function Clean($string) {
    return htmlspecialchars($string, ENT_QUOTES, 'UTF-8');
}
```

**SAST Detection:** Any SAST tool (e.g., Semgrep, PHPStan with security rules, SonarQube) would flag these as critical. Rule: `php.lang.security.injection.tainted-sql-string`.

**Remediation:**
1. **Immediate:** Migrate all queries to `mysqli_prepare()` / `mysqli_stmt_bind_param()` (parameterized queries)
2. **Short-term:** Introduce a database abstraction layer (PDO with prepared statements)
3. **Validation:** Run DAST scan (OWASP ZAP, sqlmap) against all endpoints to confirm remediation

---

### CRIT-02: Hardcoded Secrets in Kubernetes Manifests

**CWE:** CWE-798 (Use of Hard-coded Credentials)
**OWASP:** A07:2021 (Identification and Authentication Failures)
**Affected Files:**
- `services/wiki/k8s/02-secret.yaml` - base64-encoded DB credentials (`wikiuser`/`wikipass`)
- `services/wiki/k8s/05-web.yaml` - plaintext passwords in env vars (lines 128-134):
  ```yaml
  - name: LOGIN_PASSWORD
    value: "changeme"
  - name: ADMIN_PASSWORD
    value: "changeme"
  - name: BAN_PASSWORD
    value: "changeme"
  ```

**Description:**
Kubernetes Secrets with base64-encoded values are committed to source control. Base64 is encoding, not encryption. Additionally, application passwords are set as plaintext environment variables directly in deployment manifests. These are visible to anyone with repo access and will persist in git history indefinitely.

**Remediation:**
1. **Immediate:** Remove `02-secret.yaml` from git tracking; add to `.gitignore`
2. **Short-term:** Implement sealed-secrets (Bitnami) or External Secrets Operator (ESO) backed by a secrets manager
3. **Production:** Integrate with HashiCorp Vault, AWS Secrets Manager, or similar KMS
4. **Git history:** Consider BFG Repo Cleaner to purge secrets from history before going public
5. Move all `LOGIN_PASSWORD`, `ADMIN_PASSWORD`, `BAN_PASSWORD`, `CAPTCHA_BYPASS` to Secret resources

---

### CRIT-03: No TLS Termination - OWASP A02:2021 (Cryptographic Failures)

**CWE:** CWE-319 (Cleartext Transmission of Sensitive Information)
**Affected Files:**
- `services/wiki/k8s/06-ingress.yaml`
- `infrastructure/traefik/deployment.yaml`

**Description:**
All traffic between clients and the cluster, and between Traefik and backend services, is transmitted over plaintext HTTP. No TLS certificates are configured. Authentication cookies, passwords, and user data traverse the network unencrypted.

**Remediation:**
1. **Dev environment:** Deploy cert-manager with self-signed ClusterIssuer; add `tls` section to IngressRoute
2. **Staging/Production:** Use cert-manager with Let's Encrypt (ACME) ClusterIssuer
3. **Internal:** Enable mTLS between services via a service mesh (Linkerd/Istio) or Traefik's built-in mTLS
4. Add `Strict-Transport-Security` (HSTS) response header via Traefik middleware

---

### CRIT-04: Container Images Run as Root

**CWE:** CWE-250 (Execution with Unnecessary Privileges)
**Affected Files:**
- `services/wiki/Dockerfile.php` - runs php-fpm as root (final `USER root` on line 51)
- `services/wiki/Dockerfile.nginx` - default nginx root user
- `services/wiki/k8s/05-web.yaml` - no `securityContext` defined

**Description:**
Both containers in the wiki pod run as UID 0 (root). Container breakout exploits (e.g., CVE-2024-21626 runc, CVE-2022-0185 kernel) become full node compromises when the container runs as root.

**Remediation:**

> **Note (2026-02-18):** The `runAsNonRoot: true` and `capabilities: drop: ["ALL"]` recommendations were applied but caused `CreateContainerConfigError` and `CrashLoopBackOff` across all services. The standard nginx, php-fpm, and MariaDB images all require root. These restrictions have been rolled back to `seccompProfile: RuntimeDefault` only. Proper non-root support requires custom image builds with non-root USER instructions, which is deferred to the production hardening phase.

1. **Current state:** Pod-level `seccompProfile: RuntimeDefault` is applied. Container-level privilege restrictions are deferred.
2. **Future (prod hardening):** Rebuild images with non-root USER, add `readOnlyRootFilesystem`, `tmpfs` mounts for writable dirs, and `capabilities: drop: ["ALL"]`
3. **Exception:** Traefik v2.11 supports non-root natively (`runAsUser: 65532`) and has full restrictions applied
4. **Exception:** MariaDB will always need elevated capabilities (CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID) for data directory initialization

---

### CRIT-05: Deprecated/Removed PHP Functions - Runtime Crash Risk

**CWE:** CWE-477 (Use of Obsolete Function)
**Affected File:** `services/wiki/wwwroot/fishlib.php`

**Description:**
`create_function()` was deprecated in PHP 7.2 and **removed in PHP 8.0**. The current runtime is PHP 8.2. Any code path that hits `create_function()` will throw a fatal error. This is both a stability and security issue (it used `eval()` internally).

**Remediation:**
1. Replace all `create_function()` calls with anonymous functions (closures):
   ```php
   // Before (broken on PHP 8.0+)
   $func = create_function('$a', 'return $a * 2;');
   // After
   $func = function($a) { return $a * 2; };
   ```
2. Audit all PHP files for other deprecated/removed functions: `ereg()`, `split()`, `mysql_*()`, `each()`

---

### CRIT-06: Arbitrary Function Execution via API

**CWE:** CWE-470 (Use of Externally-Controlled Input to Select Classes or Code)
**OWASP:** A03:2021 (Injection)
**Affected File:** `services/wiki/wwwroot/api/v1/api.php`

**Description:**
The API router uses `call_user_func()` with user-supplied method names from the HTTP request. An attacker can invoke arbitrary PHP functions by crafting the request path/parameters.

**Remediation:**
1. Implement an explicit allowlist of permitted API methods:
   ```php
   $allowed = ['getPage', 'search', 'getRecent'];
   if (!in_array($method, $allowed, true)) {
       http_response_code(404);
       exit;
   }
   ```
2. Never pass unsanitized user input to `call_user_func()`, `call_user_func_array()`, or variable function calls

---

## High Findings (P1)

### HIGH-01: No Network Policies - Lateral Movement Risk

**CIS Benchmark:** 5.3.2 - Ensure that all Namespaces have Network Policies defined
**Affected:** Entire `wetfish-dev` namespace

**Description:**
No Kubernetes NetworkPolicies exist. Any compromised pod can reach any other pod/service in the cluster, including the MySQL database directly, the Kubernetes API server, and the cloud metadata endpoint (169.254.169.254).

**Remediation:**
1. Create a default-deny ingress/egress policy for the namespace
2. Create explicit allow policies:
   - wiki-web -> wiki-mysql:3306 (egress)
   - traefik -> wiki-web:80 (ingress)
   - wiki-web -> DNS (kube-dns:53, egress)
3. Block access to metadata endpoints and node-local services

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: wetfish-dev
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

---

### HIGH-02: No RBAC Scoping / ServiceAccount Hardening

**CIS Benchmark:** 5.1.5 - Ensure default ServiceAccount is not actively used
**Affected:** All deployments in `wetfish-dev`

**Description:**
All pods use the `default` ServiceAccount with auto-mounted API tokens. A compromised container can query the Kubernetes API and potentially escalate privileges.

**Remediation:**
1. Create dedicated ServiceAccounts per workload with `automountServiceAccountToken: false`
2. Apply least-privilege RBAC roles where API access is genuinely needed
3. Add to pod spec:
   ```yaml
   serviceAccountName: wiki-web-sa
   automountServiceAccountToken: false
   ```

---

### HIGH-03: No Resource Quotas or LimitRanges

**CIS Benchmark:** 5.2.x
**Affected:** `wetfish-dev` namespace

**Description:**
No `ResourceQuota` or `LimitRange` objects exist. A single misbehaving pod can consume all node resources (CPU, memory, storage), causing denial of service to other workloads.

**Remediation:**
1. Create `LimitRange` to set default requests/limits for containers
2. Create `ResourceQuota` to cap total namespace resource consumption
3. Review existing resource limits in deployments for appropriateness

---

### HIGH-04: Session Configuration Weaknesses

**CWE:** CWE-614 (Sensitive Cookie in HTTPS Session Without 'Secure' Attribute)
**OWASP:** A07:2021 (Identification and Authentication Failures)
**Affected Files:**
- `services/wiki/config/php.ini`
- `services/wiki/wwwroot/api/v1/api.php`

**Description:**
PHP session cookies lack `Secure`, `HttpOnly`, and `SameSite` attributes. Session IDs can be stolen via XSS or transmitted over HTTP. No CSRF tokens are implemented on state-changing endpoints.

**Remediation:**
1. Update `php.ini`:
   ```ini
   session.cookie_httponly = 1
   session.cookie_secure = 1
   session.cookie_samesite = Strict
   session.use_strict_mode = 1
   ```
2. Implement CSRF token generation and validation on all POST endpoints
3. Set session ID regeneration on privilege change (`session_regenerate_id(true)`)

---

### HIGH-05: Nginx Security Headers Missing

**OWASP:** A05:2021 (Security Misconfiguration)
**Affected File:** `services/wiki/config/nginx.conf`

**Description:**
No security headers are set. `autoindex on` is enabled on the root location, exposing directory listings. Missing headers: CSP, X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy.

**Remediation:**
1. Remove `autoindex on` immediately
2. Add security headers:
   ```nginx
   add_header X-Content-Type-Options "nosniff" always;
   add_header X-Frame-Options "SAMEORIGIN" always;
   add_header X-XSS-Protection "1; mode=block" always;
   add_header Referrer-Policy "strict-origin-when-cross-origin" always;
   add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';" always;
   add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
   ```
3. Restrict access to sensitive paths (`.php` files in non-public directories, `.git`, `.env`)

---

### HIGH-06: CI/CD Pipeline Missing Security Gates

**Affected Files:**
- `.github/workflows/build-wiki-nginx.yml`
- `.github/workflows/build-wiki-php.yml`

**Description:**
GitHub Actions workflows build and push images without any security scanning. No SAST, container image scanning, SBOM generation, or vulnerability checks are performed in the pipeline.

**Remediation:**
1. Add container image scanning (Trivy, Grype, or Snyk):
   ```yaml
   - name: Scan image for vulnerabilities
     uses: aquasecurity/trivy-action@master
     with:
       image-ref: ${{ env.IMAGE_NAME }}
       severity: 'CRITICAL,HIGH'
       exit-code: '1'
   ```
2. Add SAST step (Semgrep or PHPStan with security rules)
3. Generate SBOM with Syft/Trivy for supply chain transparency
4. Pin GitHub Actions to SHA digests (not tags) to prevent supply chain attacks
5. Add CODEOWNERS and branch protection rules requiring review

---

## Medium Findings (P2)

### MED-01: Base Images Not Pinned to Digest

**CWE:** CWE-1104 (Use of Unmaintained Third Party Components)
**Supply Chain Risk**

**Affected Files:**
- `services/wiki/Dockerfile.php` - `FROM docker.io/debian:bookworm-slim`
- `services/wiki/Dockerfile.nginx` - `FROM docker.io/debian:bookworm-slim`
- `services/wiki/k8s/03-mysql.yaml` - `image: mariadb:10.10`

**Remediation:**
Pin images to SHA256 digests for reproducible builds:
```dockerfile
FROM docker.io/debian:bookworm-slim@sha256:<digest>
```

---

### MED-02: No Pod Disruption Budgets

**Affected:** All deployments

**Description:**
No PDBs defined. Node drains during maintenance will terminate all replicas simultaneously.

**Remediation:** Create PDBs with `minAvailable: 1` for critical services once replicas > 1.

---

### MED-03: PVC Storage Class Assumptions -- RESOLVED

**Affected:** `services/wiki/k8s/03-mysql.yaml`, `05-web.yaml`

**Status:** RESOLVED. Kustomize overlays now parameterize storageClassName per environment. Base manifests have no storageClassName; dev overlay patches `local-path`, staging/prod use cluster defaults.

**Remaining:**
- [ ] Implement VolumeSnapshot-based backup for MySQL data
- [ ] Document RTO/RPO targets for data recovery

---

### MED-04: `phpinfo()` Exposed on Admin Route

**CWE:** CWE-200 (Exposure of Sensitive Information)
**Affected File:** `services/wiki/wwwroot/index.php` (line ~157)

**Description:**
`phpinfo()` output is accessible via the admin route, exposing PHP version, loaded modules, environment variables (including database credentials), and server configuration.

**Remediation:** Remove `phpinfo()` call entirely, or gate behind IP allowlist + strong auth.

---

### MED-05: Regex Injection in Ban Check

**CWE:** CWE-185 (Incorrect Regular Expression)
**Affected File:** `services/wiki/wwwroot/functions.php` - `user_banned()`

**Description:**
User-controlled ban patterns are passed directly to `preg_match()` without escaping. Malicious patterns can cause ReDoS (Regular Expression Denial of Service) or bypass bans.

**Remediation:** Use `preg_quote()` on ban patterns, or switch to simple string matching (`strpos()`/`str_contains()`).

---

### MED-06: No Readiness/Startup Probes Tuning

**Affected:** `services/wiki/k8s/05-web.yaml`

**Description:**
No `startupProbe` defined. If the PHP application takes longer than `initialDelaySeconds` on cold start, the container will be killed by the liveness probe before it's ready.

**Remediation:** Add `startupProbe` with generous `failureThreshold`:
```yaml
startupProbe:
  httpGet:
    path: /
    port: 80
  failureThreshold: 30
  periodSeconds: 5
```

---

### MED-07: No Horizontal Pod Autoscaler

**Affected:** All deployments (replicas: 1)

**Description:**
Single-replica deployments have no redundancy. Any pod failure results in downtime until the replacement is scheduled.

**Remediation:** For production: set `replicas: 2` minimum and create HPA targeting CPU/memory utilization.

---

### MED-08: Docker Compose Files Reference Incorrect Service Names

**Affected Files:**
- `services/wiki/docker-compose.yml`
- `services/wiki/docker-compose.dev.yml`
- `services/wiki/docker-compose.staging.yml`

**Description:**
Docker Compose files may reference stale service names or configurations that have diverged from the Kubernetes manifests during migration. These should be kept in sync or deprecated.

**Remediation:** Either update docker-compose files to match current architecture or mark them as deprecated/dev-only with a notice.

---

### MED-09: Monitoring Stack Not Deployed -- RESOLVED

**Affected:** `monitoring/values/*.yaml`

**Status:** RESOLVED. Full monitoring stack deployed to `wetfish-monitoring` namespace:
- kube-prometheus-stack (Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics)
- Loki (log aggregation, SingleBinary mode)
- Tempo (distributed tracing)
- Promtail (DaemonSet log collector shipping to Loki)
- Grafana has 4 pre-configured datasources (Prometheus, Alertmanager, Loki, Tempo)
- Wiki ServiceMonitors created for Prometheus target discovery

**Remaining:**
- [ ] Create custom alert rules for: pod restarts, high error rates, resource pressure
- [ ] Add ServiceMonitors for click, danger, glitch services

---

### MED-10: No Backup Strategy for Persistent Data

**Affected:** MySQL PVC, uploads PVC, wwwroot PVC

**Description:**
No automated backup mechanism exists for any persistent data. PVC loss (node failure, accidental deletion) results in total data loss.

**Remediation:**
1. Implement CronJob-based `mysqldump` to object storage
2. Use Velero or similar for PVC snapshot/restore
3. Test restore procedures quarterly

---

## Low Findings (P3)

### LOW-01: `ALLOWED_EMBEDS` Empty String May Bypass Validation

**Affected:** `services/wiki/k8s/05-web.yaml` line 126
**Remediation:** Review application logic; set explicit deny if empty means "allow all".

### LOW-02: No Pod Anti-Affinity Rules

**Affected:** All deployments
**Remediation:** Add `podAntiAffinity` to spread replicas across nodes when scaling.

### LOW-03: No Annotations for Monitoring/Alerting

**Affected:** All Service/Deployment objects
**Remediation:** Add Prometheus scrape annotations (`prometheus.io/scrape: "true"`) where applicable.

### LOW-04: Labels Inconsistency

**Affected:** Various k8s manifests
**Remediation:** Standardize on Kubernetes recommended labels (`app.kubernetes.io/name`, `app.kubernetes.io/component`, `app.kubernetes.io/version`).

### LOW-05: Init Container Uses `cp -rn` Without Error Handling

**Affected:** `services/wiki/k8s/05-web.yaml` line 57
**Description:** `cp -rn ... || true` silently swallows copy failures.
**Remediation:** Add validation step or use `rsync` with proper error handling.

### LOW-06: No Image Pull Policy Specified

**Affected:** All container specs
**Remediation:** Set `imagePullPolicy: Always` for `latest`-like tags, `IfNotPresent` for versioned tags.

### LOW-07: Traefik Dashboard Exposure

**Affected:** `infrastructure/traefik/dashboard.yaml`
**Remediation:** Restrict dashboard access to internal network or add BasicAuth middleware.

### LOW-08: No `deny` Rule for Sensitive File Types in Nginx

**Affected:** `services/wiki/config/nginx.conf`
**Remediation:**
```nginx
location ~ /\.(git|env|htaccess|htpasswd) {
    deny all;
    return 404;
}
```

---

## OWASP Top 10 (2021) Coverage Matrix

| # | Category | Status | Findings |
|---|----------|--------|----------|
| A01 | Broken Access Control | FAIL | CRIT-06, HIGH-02 |
| A02 | Cryptographic Failures | FAIL | CRIT-03, HIGH-04 |
| A03 | Injection | FAIL | CRIT-01, CRIT-06, MED-05 |
| A04 | Insecure Design | WARN | No threat model, no abuse case analysis |
| A05 | Security Misconfiguration | FAIL | CRIT-04, HIGH-01, HIGH-05, LOW-07 |
| A06 | Vulnerable/Outdated Components | WARN | CRIT-05, MED-01 |
| A07 | Identification & Auth Failures | FAIL | CRIT-02, HIGH-04 |
| A08 | Software & Data Integrity Failures | WARN | HIGH-06, MED-01 |
| A09 | Security Logging & Monitoring | PARTIAL | MED-09 (stack deployed, custom alerts pending) |
| A10 | Server-Side Request Forgery | PASS | No SSRF vectors identified |

---

## Recommended Remediation Roadmap

### Phase 1: Pre-Production Gate (Week 1-2)
- [ ] CRIT-02: Move secrets out of git; implement sealed-secrets or external secrets
- [ ] CRIT-04: Add securityContext to all pod specs
- [ ] HIGH-01: Deploy default-deny NetworkPolicy
- [ ] HIGH-02: Create dedicated ServiceAccounts
- [ ] HIGH-05: Add nginx security headers; remove `autoindex on`
- [ ] MED-04: Remove `phpinfo()` exposure

### Phase 2: Security Hardening (Week 3-6)
- [ ] CRIT-01: Begin SQL injection remediation (parameterized queries) - highest effort item
- [ ] CRIT-03: Deploy cert-manager + TLS termination
- [ ] CRIT-05: Replace `create_function()` and audit for removed PHP functions
- [ ] CRIT-06: Implement API method allowlist
- [ ] HIGH-04: Harden PHP session configuration
- [ ] HIGH-06: Add Trivy scanning + SAST to CI/CD pipeline

### Phase 3: Operational Maturity (Week 7-12)
- [ ] HIGH-03: Deploy ResourceQuota and LimitRange
- [x] MED-03: ~~Parameterize storage class per environment~~ (done via Kustomize overlays)
- [ ] MED-06: Add startup probes
- [x] MED-09: ~~Deploy monitoring stack~~ (Prometheus, Grafana, Loki, Tempo, Promtail deployed)
- [ ] MED-10: Implement automated backup strategy
- [ ] LOW-*: Address remaining low-severity findings

### Phase 4: Continuous Security (Ongoing)
- [ ] Integrate DAST scanning (OWASP ZAP) into staging pipeline
- [ ] Establish vulnerability management SLA (Critical: 7d, High: 30d, Medium: 90d)
- [ ] Schedule quarterly penetration testing
- [ ] Implement runtime security monitoring (Falco or Tetragon)
- [ ] Conduct threat modeling exercise for new services

---

## Tools & References

| Tool | Purpose | Integration Point |
|------|---------|-------------------|
| [Trivy](https://github.com/aquasecurity/trivy) | Container image CVE scanning, SBOM | CI/CD pipeline |
| [Semgrep](https://semgrep.dev) | SAST for PHP SQL injection, XSS | CI/CD pipeline, pre-commit |
| [OWASP ZAP](https://www.zaproxy.org) | DAST - automated penetration testing | Staging environment |
| [cert-manager](https://cert-manager.io) | TLS certificate lifecycle | Kubernetes cluster |
| [sealed-secrets](https://github.com/bitnami-labs/sealed-secrets) | Encrypted secrets in git | Kubernetes cluster |
| [Falco](https://falco.org) | Runtime security monitoring | Kubernetes cluster |
| [Velero](https://velero.io) | Backup/restore for PVCs | Kubernetes cluster |
| [kube-bench](https://github.com/aquasecurity/kube-bench) | CIS Kubernetes Benchmark | Cluster hardening audit |

---

*This document should be reviewed and updated after each remediation phase. Findings should be tracked in the project issue tracker with appropriate labels and assignees.*
