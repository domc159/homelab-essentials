# HomeServer

One-script self-hosted stack for Ubuntu Server. Installs, configures, and starts a full suite of services via Docker with randomised secrets and isolated networks.

## Services

| Service | Port | Description |
|---|---|---|
| [Webmin](https://www.webmin.com/) | `10000` (HTTPS) | Server administration |
| [Seafile](https://www.seafile.com/) | `8060` | File sync & cloud storage |
| [BentoPDF](https://github.com/alam00000/bentopdf) | `8061` | PDF tools |
| [IT-Tools](https://it-tools.tech/) | `8062` | Developer utility toolbox |
| [FreshRSS](https://freshrss.org/) | `8063` | RSS aggregator |
| [Immich](https://immich.app/) | `8064` | Photo & video backup |
| [Joplin Server](https://joplinapp.org/) | `8065` | Note-taking sync server |
| [Paperless-ngx](https://docs.paperless-ngx.com/) | `8066` | Document management |
| [n8n](https://n8n.io/) | `8067` | Workflow automation |
| [OnlyOffice](https://www.onlyoffice.com/) | `8068` | Online office suite |

## Requirements

- Ubuntu Server 22.04 / 24.04
- Root or `sudo` access

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/install.sh -o install.sh
sudo bash install.sh
```

The script installs Docker and Webmin, creates data directories, generates `/home/homelab/.env` with random passwords, writes `docker-compose.yml`, and starts all containers.

## Configuration

Secrets and settings are stored in `/home/homelab/.env` (auto-generated, `chmod 600`). Notable defaults to review:

```dotenv
SERVER_IP=<auto-detected>
TZ=Europe/Ljubljana
SEAFILE_ADMIN_EMAIL=me@mail.com
SEAFILE_ADMIN_PASSWORD=admin   # change after first login
```

All database passwords, secret keys, and JWT tokens are randomly generated on first run. Re-running the script will not overwrite an existing `.env`.

## Managing Services

```bash
cd /home/homelab
docker compose ps                             # status
docker compose logs -f <service>             # logs
docker compose pull && docker compose up -d  # update
docker compose down                          # stop all
```

## Notes

- Seafile and Immich take 1–2 minutes to initialise on first start.
- The `.env` file contains secrets — do not commit it to git.
- For external access, place services behind a reverse proxy (Caddy, Nginx Proxy Manager, Traefik) with valid TLS.

## Uninstall

```bash
cd /home/homelab && docker compose down -v
rm -rf /home/homelab /home/homelab_data /home/data
apt-get remove --purge webmin
```
