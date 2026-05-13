# Forum Deployment Runbook

Step-by-step process for deploying the Wetfish SMF 2.1.6 forum to a new environment (dev, staging, or prod).

## Prerequisites

- k3d cluster running (`./scripts/up.sh`)
- Forum images built and pushed to registry
- `smf_data.sql` available (output of the upgrade pipeline in `~/git/forum/projects/smf-docker/`)
- Mod packages built in `~/git/forum/dist/`
- Third-party packages in `~/git/forum/to-install/`

---

## Step 1 — Build and Push Forum Images

```bash
docker build -t localhost:5000/forum:nginx -f services/forum/Dockerfile.nginx services/forum/
docker build -t localhost:5000/forum:php   -f services/forum/Dockerfile.php   services/forum/

docker push localhost:5000/forum:nginx
docker push localhost:5000/forum:php
```

For staging/prod, CI/CD handles this via GitHub Actions.

---

## Step 2 — Deploy the Forum Service

```bash
./scripts/deploy.sh --env dev forum
```

Verify pods are running:

```bash
kubectl get pods -n wetfish-dev -l app=forum
```

Expected: `forum-web` (2/2 Running), `forum-mysql` (1/1 Running).

---

## Step 3 — Add /etc/hosts Entry (dev only)

```bash
echo "127.0.0.1 forum.wetfish.local" | sudo tee -a /etc/hosts
```

---

## Step 4 — Import the Migrated Database

The `smf_data.sql` dump is produced by the upgrade pipeline (`~/git/forum/projects/smf-docker/scripts/upgrade.sh`). It uses the database name `new_forum` which must be rewritten to match the k8s environment (`forumdb` for dev).

```bash
LC_ALL=C sed 's/`new_forum`/`forumdb`/g; s/USE `new_forum`/USE `forumdb`/g' \
  ~/git/forum/projects/smf-docker/smf_data.sql \
  | kubectl exec -i deployment/forum-mysql -n wetfish-dev -- \
    mysql -uforumuser -pforumpass forumdb
```

> **Note:** `LC_ALL=C` is required — the dump contains non-ASCII characters (forum posts) that cause `sed` to fail with "illegal byte sequence" on macOS without it.

Verify the import:

```bash
kubectl exec -i deployment/forum-mysql -n wetfish-dev -- \
  mysql -uforumuser -pforumpass forumdb -e \
  "SELECT COUNT(*) FROM smf_members; SELECT COUNT(*) FROM smf_messages;"
```

Expected: ~504 members, ~32,103 messages.

---

## Step 5 — Fix Environment-Specific URLs in the Database

The dump was generated from a local Docker environment at `http://127.0.0.1:8080`. Several URLs are stored as absolute values in the database and must be updated for the target environment.

### Fix theme URLs

```bash
kubectl exec -i deployment/forum-mysql -n wetfish-dev -- \
  mysql -uforumuser -pforumpass forumdb -e "
UPDATE smf_themes
SET value = REPLACE(value, 'http://127.0.0.1:8080', 'http://forum.wetfish.local:8080')
WHERE variable IN ('theme_url', 'images_url');"
```

For staging/prod, replace `http://forum.wetfish.local:8080` with the appropriate base URL (e.g. `https://forum.wetfish.net`).

### Fix board description currency icon URLs

Board descriptions contain hardcoded `<img>` tags pointing to `https://wetfishonline.com/forum/fish/img/coins/coral.png` (the production server). These break in any non-production environment.

Replace with the relative path to the WFIE currency icon that ships with the mod:

```bash
kubectl exec -i deployment/forum-mysql -n wetfish-dev -- \
  mysql -uforumuser -pforumpass forumdb -e "
UPDATE smf_boards
SET description = REPLACE(
  description,
  'https://wetfishonline.com/forum/fish/img/coins/coral.png',
  '/images/wf-item-econ/economy/currency-icon.png'
)
WHERE description LIKE '%wetfishonline.com%';"
```

> **Root cause:** The board descriptions were authored with an absolute URL to the production asset. This is stored as raw HTML in `smf_boards.description`. The fix uses the relative WFIE currency icon path which resolves correctly in all environments.
>
> **Prod action item:** Update the board descriptions in the live forum admin panel to use the relative path so future dumps are portable.

### Fix custom avatar URL

The `custom_avatar_url` setting in `smf_settings` is stored as an absolute URL from the dump origin and must be updated:

```bash
kubectl exec -i deployment/forum-mysql -n wetfish-dev -- \
  mysql -uforumuser -pforumpass forumdb -e "
UPDATE smf_settings
SET value = 'http://forum.wetfish.local:8080/custom_avatar'
WHERE variable = 'custom_avatar_url';"
```

For staging/prod, replace the URL with the environment's base URL (e.g. `https://staging-forums.wetfish.net/custom_avatar`).

### Insert boardurl setting

`boardurl` may be absent from the dump. Insert or update it:

```bash
kubectl exec -i deployment/forum-mysql -n wetfish-dev -- \
  mysql -uforumuser -pforumpass forumdb -e "
INSERT INTO smf_settings (variable, value)
VALUES ('boardurl', 'http://forum.wetfish.local:8080')
ON DUPLICATE KEY UPDATE value = 'http://forum.wetfish.local:8080';"
```

### Fix YouTube embed regex (SAVE mod)

The Simple Audio Video Embedder (SAVE) ships with a YouTube regex that requires a subdomain before `youtube.` — bare `youtube.com` links fail. Patch after mod install:

```bash
kubectl exec -i deployment/forum-mysql -n wetfish-dev -- mysql -uforumuser -pforumpass forumdb << 'EOF'
UPDATE smf_mediapro_sites
SET regexmatch = 'htt(p|ps)://(www\\.)?youtube\\.[\\w]+/watch[(\\?|\\?feature=player_embedded&amp;)\\#!]+v=([\\w-]+)[\\w&;+-]*[\\#&;t=]*([\\d]*)[&;10wshdq=]*'
WHERE id = 1;
EOF
```

> **Root cause:** The original regex used `[\\w.]+youtube\\.` which requires at least one character before `youtube.` — bare `youtube.com` has no subdomain so it never matches. The fix makes the `www.` optional with `(www\\.)?`.

### Clear SMF cache

After any DB URL changes, clear SMF's file cache:

```bash
kubectl exec deployment/forum-web -n wetfish-dev -c php-fpm -- \
  find /var/www/forum/cache -name "*.cache" -delete
```

---

## Step 6 — Reset Admin Password (dev/staging only)

The admin account in the migrated dataset is `shitsubject` (id=1). Reset to a known password for local testing:

```bash
kubectl exec -i deployment/forum-mysql -n wetfish-dev -- \
  mysql -uforumuser -pforumpass forumdb -e \
  "UPDATE smf_members SET passwd=SHA1(CONCAT(LOWER('shitsubject'), 'admin')) WHERE id_member=1;"
```

Login at `http://forum.wetfish.local:8080/index.php?action=login`:
- **Username:** `shitsubject`
- **Password:** `admin`

> Do not do this in production.

---

## Step 7 — Install Mod Packages

Copy all mod packages into the running container:

```bash
POD=$(kubectl get pod -n wetfish-dev -l app=forum,component=web -o jsonpath='{.items[0].metadata.name}')

for f in ~/git/forum/dist/*.tar.gz; do
  kubectl cp "$f" wetfish-dev/$POD:/var/www/forum/Packages/ -c php-fpm
done

for f in ~/git/forum/to-install/*.zip; do
  kubectl cp "$f" wetfish-dev/$POD:/var/www/forum/Packages/ -c php-fpm
done

kubectl exec -n wetfish-dev $POD -c php-fpm -- \
  chown -R www-data:www-data /var/www/forum/Packages/
```

Then install via the SMF Package Manager UI:

`http://forum.wetfish.local:8080/index.php?action=admin;area=packages`

**Install in this order — do not configure any mod when prompted, just install:**

Wetify mods (no DB tables):
1. Rainbow BBC
2. Mobile BBC Button Styling
3. Additional CSS Classes
4. Mail Vars

Wetify mods (with DB tables):
5. Items & Economy
6. Topicmaster
7. Wetify

3rd party mods:
8. Simple Audio Video Embedder
9. Optimus
10. SoundCloud Embed Widget

---

## Step 8 — Install the FishTank Theme

Navigate to: `http://forum.wetfish.local:8080/index.php?action=admin;area=theme;sa=admin`

- **Install a New Theme** → From an archive
- Upload `~/git/forum/dist/fishtank.tar.gz`
- After install:
  - Set **Overall Forum Default** → `fishtank`
  - Set **Reset everyone to** → `fishtank`
  - Uncheck **"Allow members to select their own themes"**

---

## Known Issues

### Theme URLs are absolute in the dump

`smf_themes.theme_url` and `images_url` for the fishtank theme are stored as absolute URLs referencing the environment where the theme was installed. Must be updated after every import (see Step 5).

### Board description currency icon is hardcoded to production

`smf_boards.description` fields contain `<img src="https://wetfishonline.com/forum/fish/img/coins/coral.png">`. These were written as raw HTML into the board description by an admin. They will 404 in any non-production environment until the production board descriptions are updated to use the relative path `/images/wf-item-econ/economy/currency-icon.png`.

### DB name differs between smf-docker and k8s

The upgrade pipeline produces `smf_data.sql` with `new_forum` as the database name. The k8s deployments use environment-specific names (`forumdb` in dev). Always use the `LC_ALL=C sed` rewrite on import.

### SITE_BOARDURL must match the environment

`services/forum/k8s/overlays/dev/env-patch.yaml` must set `SITE_BOARDURL` to `http://forum.wetfish.local:8080` (HTTP, with port). Using `https://` or omitting the port causes redirect loops or broken asset URLs.

### custom_avatar_url is absolute in the dump

`smf_settings.custom_avatar_url` is stored as an absolute URL from the source environment (`http://127.0.0.1:8080/custom_avatar`). Custom avatar uploads will be served from the wrong host in any other environment. Update via Step 5.

### boardurl may be missing from the dump

The `boardurl` key in `smf_settings` is sometimes absent from the migrated dump. Insert it explicitly in Step 5.

### SAVE mod YouTube regex requires www. subdomain

The Simple Audio Video Embedder ships with a YouTube regex that does not match bare `youtube.com` URLs (only `www.youtube.com`). Apply the `smf_mediapro_sites` patch in Step 5 after mod install.

### og:image missing — wetfish-online-social.png not in FishTank theme

`Themes/fishtank/images/wetfish-online-social.png` is referenced by the Optimus mod for social share previews but is not included in the distributed theme archive. The `og:image` meta tag will be absent until this file is added to the theme or bundled in the Docker image.
