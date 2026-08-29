# Ledgix_pos

> **A clean Frappe v15 ERP deployment toolkit for Ledgix SaaS — built for local development, site setup, production deployment, backups, updates, and server operations.**

---

<div align="center">

# Ledgix SaaS Deployment Kit

**Local setup. Production deployment. Site management. App installation. One clean workflow.**

</div>

---

## Overview

`Ledgix POS` is a complete setup and deployment repository for running **Ledgix SaaS** on the Frappe Framework.

It includes scripts for:

* Local Frappe development setup
* Bench initialization
* Site creation
* Ledgix SaaS app installation
* Local bench start/restart
* Production EC2/server deployment
* Nginx, Supervisor, SSL, backup, update, and status helpers
* Local CI-style validation, secret scanning, and smoke testing

The repository is designed to keep the full ERP setup process organized, repeatable, and production-friendly.

---

## Project Snapshot

```text
┌─────────────────────────────────────────────────────────────┐
│                         Ledgix POS                            │
├─────────────────────────────────────────────────────────────┤
│ Framework      │ Frappe v15                                 │
│ Main App       │ Ledgix SaaS                                │
│ Environment    │ Local Development + Production Server       │
│ Database       │ MariaDB                                    │
│ Cache/Queue    │ Redis                                      │
│ Web Server     │ Nginx for production                        │
│ Process Manager│ Supervisor for production                   │
│ Local Runner   │ bench start                                │
└─────────────────────────────────────────────────────────────┘
```

---

## What This Repository Includes

```text
┌─────────────────────┬───────────────────────────────────────┐
│ Area                │ Purpose                               │
├─────────────────────┼───────────────────────────────────────┤
│ install.sh          │ Main setup launcher                    │
│ site_setup.sh       │ Local site creation and app install    │
│ start.sh            │ Local bench start/restart helper       │
│ deploy/             │ Production deployment helpers          │
│ scripts/            │ Local validation and secret checks      │
│ docs/               │ Production, FBR, command, troubleshoot  │
│ docs/production/SECURITY.md │ Security policy and deployment notes    │
│ config/example.env  │ Private environment template            │
│ env/                │ Example environment templates          │
│ tools/cleanup/      │ Cleanup/helper scripts                 │
│ apps/ledgix_saas   │ Custom Ledgix SaaS Frappe app          │
└─────────────────────┴───────────────────────────────────────┘
```

---

## Core Workflow

```text
┌──────────────┐
│ Clone Repo   │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Run Installer│
└──────┬───────┘
       │
       ├───────────────────────┐
       │                       │
       ▼                       ▼
┌──────────────────┐   ┌─────────────────────┐
│ Local Setup      │   │ Production Setup     │
│ bench start      │   │ Nginx + Supervisor   │
│ port 8000        │   │ ports 80 / 443       │
└──────┬───────────┘   └──────────┬──────────┘
       │                          │
       ▼                          ▼
┌──────────────────┐   ┌─────────────────────┐
│ Create Site      │   │ Configure Domain     │
└──────┬───────────┘   └──────────┬──────────┘
       │                          │
       ▼                          ▼
┌──────────────────┐   ┌─────────────────────┐
│ Install Ledgix   │   │ Enable SSL / Backups │
└──────┬───────────┘   └──────────┬──────────┘
       │                          │
       ▼                          ▼
┌──────────────────┐   ┌─────────────────────┐
│ Start Working    │   │ Live ERP Deployment  │
└──────────────────┘   └─────────────────────┘
```

---

## Ledgix SaaS App

Ledgix SaaS is the main custom Frappe app included in this repository.

The app is stored inside:

```text
apps/ledgix_saas/
```

### App Structure

```text
apps/ledgix_saas/
├── api/
├── config/
├── fixtures/
├── ledgix/
├── ledgix_saas.egg-info/
├── ledgix_saas/setup/
├── patches/
├── public/
├── setup/
├── templates/
├── www/
├── __init__.py
├── hooks.py
├── modules.txt
├── patches.txt
└── pyproject.toml
```

### Ledgix SaaS Covers

```text
┌─────────────────────┬───────────────────────────────────────┐
│ Module Area         │ Description                           │
├─────────────────────┼───────────────────────────────────────┤
│ API Layer           │ Backend endpoints and integrations     │
│ Config              │ App configuration and setup logic      │
│ Fixtures            │ Exported roles, settings, and records  │
│ Patches             │ Versioned database/app migrations      │
│ Public Assets       │ Static files and frontend assets        │
│ Templates           │ Jinja/web templates                    │
│ Web Pages           │ Website routes and public pages         │
│ Setup               │ App installation/setup utilities        │
└─────────────────────┴───────────────────────────────────────┘
```

---

## Quick Start

Clone the repository:

```bash
git clone https://github.com/mshahwaiz-ali/pos.git
cd pos
```

Make scripts executable:

```bash
chmod +x install.sh site_setup.sh start.sh
```

Run the installer:

```bash
./install.sh
```

Choose local setup:

```text
1) Local / Development Setup
```

Create or manage a site:

```bash
./site_setup.sh
```

Start local bench:

```bash
./start.sh
```

Open your site:

```text
http://your-site.local:8000
```

Example:

```text
http://ledgix.local:8000
```

---

## Local vs Production

```text
┌─────────────────────┬─────────────────────┬─────────────────────┐
│ Area                │ Local Development   │ Production Server   │
├─────────────────────┼─────────────────────┼─────────────────────┤
│ Runner              │ bench start         │ Supervisor          │
│ Web Server          │ Bench dev server    │ Nginx               │
│ Port                │ 8000                │ 80 / 443            │
│ SSL                 │ Not required        │ Certbot / HTTPS     │
│ Logs                │ Local logs          │ Production logs     │
│ Best For            │ Development/testing │ Live deployment     │
│ Main Script         │ start.sh            │ deploy scripts      │
└─────────────────────┴─────────────────────┴─────────────────────┘
```

---

## Production Deployment

Production helpers are stored in:

```text
deploy/
```

Available production scripts:

```text
deploy/
├── production_setup.sh
├── deploy_update.sh
├── backup.sh
├── status.sh
├── smoke_test.sh
└── docs/production/DEPLOYMENT.md
```

Run production setup:

```bash
chmod +x install.sh deploy/*.sh
./install.sh
```

Choose:

```text
2) Production / EC2 Setup
```

Or run directly:

```bash
deploy/production_setup.sh
```

Production setup is intended for real server environments and may configure:

* Required system packages
* Frappe bench
* Ledgix SaaS app sync
* Site creation
* Supervisor
* Nginx
* SSL
* Backups
* Deployment updates
* Status checks

> `start.sh` is for local development only. Do not use it as the production process manager.

---

## Recommended Documentation Map

```text
┌────────────────────────┬────────────────────────────────────┐
│ File                   │ Purpose                            │
├────────────────────────┼────────────────────────────────────┤
│ README.md              │ Project overview and quick start    │
│ docs/local/LOCAL_INSTALLATION.md │ Complete local setup guide          │
│ docs/production/DEPLOYMENT.md │ Production / EC2 deployment guide   │
│ docs/apps/APPS.md │ Ledgix SaaS app structure/details   │
│ docs/production/SECURITY.md │ Security rules and secret handling  │
│ config/example.env     │ Deployment environment template     │
│ scripts/validate_repo.sh│ Syntax/import/package validation   │
│ scripts/check_secrets.sh│ Accidental secret scanner          │
│ scripts/ci_local.sh    │ Runs validation + secret scan       │
│ deploy/smoke_test.sh   │ Offline/online deployment smoke     │
│ docs/commands/COMMANDS.md       │ Common local and production commands│
│ docs/production/PRODUCTION_CHECKLIST.md │ Production readiness checklist│
│ docs/fbr/FBR_PRODUCTION_CHECKLIST.md │ FBR go-live checklist       │
│ docs/production/TROUBLESHOOTING.md│ Common failure diagnosis            │
└────────────────────────┴────────────────────────────────────┘
```

---

## Repository Structure

```text
pos/
├── README.md
├── install.sh
├── site_setup.sh
├── start.sh
├── docs/production/SECURITY.md
│
├── config/
│   └── example.env
│
├── scripts/
│   ├── validate_repo.sh
│   ├── check_secrets.sh
│   └── ci_local.sh
│
├── docs/
│   ├── commands/COMMANDS.md
│   ├── production/PRODUCTION_CHECKLIST.md
│   ├── fbr/FBR_PRODUCTION_CHECKLIST.md
│   └── production/TROUBLESHOOTING.md
│
├── env/
│   ├── local.example.env
│   └── production.example.env
│
├── deploy/
│   ├── production_setup.sh
│   ├── deploy_update.sh
│   ├── backup.sh
│   ├── status.sh
│   ├── smoke_test.sh
│
│
├── tools/
│   └── cleanup/
│
├── apps/
│   └── ledgix_saas/
│
└── frappe-bench/
    └── generated locally, ignored by Git
```

---

## Site Strategy

Ledgix POS is structured around a clean Frappe bench workflow.

```text
┌───────────────────────────────┐
│ One Repository                │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│ One Frappe Bench              │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│ One or More Sites             │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│ Ledgix SaaS Installed Per Site│
└───────────────────────────────┘
```

Example:

```text
┌─────────────────────┬─────────────────────┐
│ Site                │ Installed App        │
├─────────────────────┼─────────────────────┤
│ ledgix.local        │ Ledgix SaaS          │
│ demo.local          │ Ledgix SaaS          │
│ client.local        │ Ledgix SaaS          │
└─────────────────────┴─────────────────────┘
```

---

## Useful Commands

Check installed apps:

```bash
bench --site your-site.local list-apps
```

Run migration:

```bash
bench --site your-site.local migrate
```

Start bench manually:

```bash
cd frappe-bench
bench start
```

Check production services:

```bash
sudo supervisorctl status
sudo nginx -t
sudo systemctl status nginx
```

Run production status helper:

```bash
deploy/status.sh
```

Run backup helper:

```bash
deploy/backup.sh
```

Run deployment update helper:

```bash
deploy/deploy_update.sh
```

Run local CI and smoke checks:

```bash
./scripts/ci_local.sh
./deploy/smoke_test.sh --site ledgix.local --offline
./start.sh --smoke --site ledgix.local
```

---

## Security Notes

Do not commit secrets, database passwords, SSL keys, backups, local logs, or generated bench files.
Setup scripts save manually entered or auto-generated site credentials to the ignored secrets files.
See `docs/production/SECURITY.md` before public production deployment.

Ignored/private files should include:

```text
secrets.md
deploy/production.secrets.md
logs/deploy/
deploy/backups-index.md
*.sql.gz
*.tar
*.tgz
.env
*.env.local
config/*.env
frappe-bench/
```

Use example files as templates:

```text
config/env/local.example.env
config/env/production.example.env
config/example.env
```

---

## Troubleshooting Quick Notes

```text
┌───────────────────────────────┬────────────────────────────────┐
│ Issue                         │ Check                          │
├───────────────────────────────┼────────────────────────────────┤
│ Site not opening locally      │ bench start / port 8000        │
│ App not installed             │ bench --site site list-apps    │
│ Migration issue               │ bench --site site migrate      │
│ Nginx welcome page            │ nginx config / default site    │
│ SSL failure                   │ DNS A record + Certbot logs    │
│ Production process down       │ supervisorctl status           │
└───────────────────────────────┴────────────────────────────────┘
```

---

## Suggested GitHub About

Description:

```text
Frappe v15 ERP deployment toolkit with local setup, EC2 production scripts, and the Ledgix SaaS custom app.
```

Topics:

```text
frappe
erpnext
erp
saas
frappe-framework
python
javascript
mariadb
redis
nginx
supervisor
deployment
ubuntu
ec2
```

---

## Notes

Ledgix POS is not just an app folder. It is a complete Frappe setup and deployment toolkit for Ledgix SaaS.

Use the local setup for development and testing. Use production deployment only on a properly prepared server.

---

## License

Private / internal project unless a license is added.

Before public distribution or commercial reuse, define the correct license and ownership terms.
