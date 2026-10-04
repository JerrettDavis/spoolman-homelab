# Spoolman homelab deployment

This repository contains the deployment, backup, verification, and operations
automation for a private [Spoolman](https://github.com/Donkie/Spoolman)
installation integrated with Home Assistant, SpoolmanSync, and two Bambu Lab
printers.

It is an environment-specific infrastructure repository, not a fork of
Spoolman. Hostnames and RFC1918 network ranges are deliberately versioned;
credentials and application data are not.

## Architecture

- Spoolman 0.27.0 and PostgreSQL 16 run as isolated Docker Compose services.
- Traefik publishes the human UI through Authentik.
- A separate exact-source endpoint lets Home Assistant reach the Spoolman API
  without interactive authentication.
- SpoolmanSync runs as a Home Assistant add-on and tracks the P2S and X2D AMS
  and external-spool positions.
- A stable HTTPS NFC/QR endpoint is restricted to the home LANs and Tailscale.
- Cloudflare DNS-01 supplies certificates without publishing NFC assignment
  pages in public DNS.

## Repository layout

```text
docs/
  SPOOLMAN-BAMBU-OPERATIONS.md
scripts/spoolman/
  compose.private.fragment.yml
  deploy-private-spoolman.sh
  publish-spoolman.sh
  publish-home-assistant-endpoint.sh
  publish-spoolmansync-nfc-endpoint.sh
  backup-spoolman.sh
  verify-*.sh
  Verify-SpoolmanSyncNfcEndpoint.ps1
  Export-SanitizedCompose.ps1
  tests/
```

## Security model

Secrets are generated or read only on the target hosts. The deployment expects
Docker secret files under `/home/jd/.docker-secrets/spoolman/`; those files are
never copied into this repository. Compose exports must pass through
`Export-SanitizedCompose.ps1` before they are retained or shared.

The root `.gitignore` is deny-by-default. It admits only the documented source
and test files and separately rejects common credentials, environment files,
certificates, keys, databases, archives, and backup formats.

Do not commit:

- `.env` or `stack.env` files;
- Docker secret contents;
- certificates containing private keys;
- Portainer exports or backups;
- Spoolman/PostgreSQL data or logical dumps;
- Home Assistant tokens, cookies, or NFC URLs containing session tokens;
- recovery evidence from live hosts.

## Validate before deployment

Run every static contract from PowerShell:

```powershell
Get-ChildItem .\scripts\spoolman\tests\*.ps1 |
    Sort-Object Name |
    ForEach-Object { & $_.FullName }
```

When connected to the home network or tailnet, verify the NFC endpoint:

```powershell
& .\scripts\spoolman\Verify-SpoolmanSyncNfcEndpoint.ps1
```

Before publishing a commit, scan the exact Git tree:

```powershell
gitleaks git --no-banner
git status --short
git ls-files
```

## Deployment order

These scripts are designed for the existing `jdh-docker-00` Portainer stack
and are intentionally idempotent. Review each script and its contract before
running it against another environment.

1. `deploy-private-spoolman.sh` creates the private database/application
   services and persistent storage.
2. `verify-private-spoolman.sh` exercises least privilege, wrong-password
   rejection, CRUD, and restart persistence.
3. `publish-spoolman.sh` publishes the Authentik-protected human endpoint.
4. `publish-home-assistant-endpoint.sh` publishes the restricted HA machine
   endpoint.
5. `publish-spoolmansync-nfc-endpoint.sh` publishes the LAN/tailnet-only NFC
   assignment endpoint.
6. `backup-spoolman.sh` and `verify-spoolman-backup.sh` create and restore-test
   the database backup.

See [the operating guide](docs/SPOOLMAN-BAMBU-OPERATIONS.md) for inventory,
NFC tag placement, Bambu Studio/OrcaSlicer use, verification, and recovery.

The Authentik application/provider, embedded-outpost callback router, Traefik
static configuration, and Cloudflare DNS credentials are external
prerequisites. They are intentionally not reproduced in this Spoolman-only
repository.

## Licensing

No license is granted by publication. Spoolman and the other referenced
projects retain their respective upstream licenses.
