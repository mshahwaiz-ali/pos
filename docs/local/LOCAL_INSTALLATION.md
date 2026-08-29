# Local Installation Guide

> **Complete local development setup guide for Ledgix POS and Ledgix SaaS on Ubuntu.**

---

<div align="center">

# Ledgix POS Local Setup

**Clone. Install. Create site. Install Ledgix SaaS. Start bench.**

</div>

---

## Overview

This guide explains how to run **Ledgix POS** locally for development and testing.

The local setup uses:

* Frappe Framework v15
* Bench CLI
* MariaDB
* Redis
* Node.js
* Yarn
* Python
* Ledgix SaaS custom app
* Local development runner through `bench start`

---

## Local Setup Flow

```text
┌──────────────────────┐
│ 1. Clone Repository  │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 2. Run install.sh    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 3. Create Site       │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 4. Install Ledgix    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 5. Start Bench       │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 6. Open in Browser   │
└──────────────────────┘
```

---

## Supported Environment

```text
┌─────────────────────┬──────────────────────────────┐
│ Component           │ Recommended                  │
├─────────────────────┼──────────────────────────────┤
│ OS                  │ Ubuntu                       │
│ Framework           │ Frappe v15                   │
│ Database            │ MariaDB                      │
│ Cache / Queue       │ Redis                        │
│ Runtime             │ Python + Node.js             │
│ Package Manager     │ Yarn                         │
│ Process Runner      │ bench start                  │
│ Browser URL         │ http://site.local:8000       │
└─────────────────────┴──────────────────────────────┘
```

---

## Repository Structure for Local Setup

```text
pos/
├── install.sh
├── site_setup.sh
├── start.sh
├── README.md
├── docs/local/LOCAL_INSTALLATION.md
├── env/
│   └── local.example.env
├── apps/
│   └── ledgix_saas/
└── frappe-bench/
    └── generated during setup
```

The `frappe-bench/` directory is generated locally and should not be committed to Git.

---

## Step 1: Clone the Repository

```bash
git clone https://github.com/mshahwaiz-ali/pos.git
cd pos
```

---

## Step 2: Make Scripts Executable

```bash
chmod +x install.sh site_setup.sh start.sh
```

If production scripts are also needed later:

```bash
chmod +x deploy/*.sh
```

---

## Step 3: Run the Installer

```bash
./install.sh
```

Select:

```text
1) Local / Development Setup
```

The local installer prepares the development environment and creates or reuses the local Frappe bench.

---

## Step 4: Create a Site

Run the site setup script:

```bash
./site_setup.sh
```

Typical site name:

```text
ledgix.local
```

During setup, provide:

```text
┌──────────────────────┬────────────────────────────────────┐
│ Input                │ Example                            │
├──────────────────────┼────────────────────────────────────┤
│ Site name            │ ledgix.local                       │
│ Administrator pass   │ Enter one, or press Enter for auto  │
│ Site DB password     │ Enter one, or press Enter for auto  │
│ Database admin user  │ Local MariaDB admin user            │
│ App selection        │ Ledgix SaaS                         │
└──────────────────────┴────────────────────────────────────┘
```

Site credentials are saved under that site's section in `secrets.md` with `600` permissions.

---

## Step 5: Install Ledgix SaaS

If the site setup script asks for app selection, choose:

```text
Ledgix SaaS
```

If you need to install manually:

```bash
cd frappe-bench
bench --site ledgix.local install-app ledgix_saas
bench --site ledgix.local migrate
```

Check installed apps:

```bash
bench --site ledgix.local list-apps
```

Expected result should include:

```text
frappe
ledgix_saas
```

---

## Step 6: Start Local Bench

From the repository root:

```bash
./start.sh
```

Or manually:

```bash
cd frappe-bench
bench start
```

---

## Step 7: Open Site in Browser

Open:

```text
http://ledgix.local:8000
```

If browser does not resolve the local site name, add it to `/etc/hosts`.

```bash
sudo nano /etc/hosts
```

Add:

```text
127.0.0.1 ledgix.local
```

Then open again:

```text
http://ledgix.local:8000
```

---

## Local URL Pattern

```text
┌──────────────────────┬────────────────────────────┐
│ Site Name            │ Local URL                  │
├──────────────────────┼────────────────────────────┤
│ ledgix.local         │ http://ledgix.local:8000   │
│ demo.local           │ http://demo.local:8000     │
│ client.local         │ http://client.local:8000   │
└──────────────────────┴────────────────────────────┘
```

---

## Common Local Commands

Go to bench directory:

```bash
cd frappe-bench
```

List sites:

```bash
bench list-sites
```

Check installed apps:

```bash
bench --site ledgix.local list-apps
```

Run migration:

```bash
bench --site ledgix.local migrate
```

Clear cache:

```bash
bench --site ledgix.local clear-cache
```

Clear website cache:

```bash
bench --site ledgix.local clear-website-cache
```

Restart local bench:

```bash
bench restart
```

Start development server:

```bash
bench start
```

---

## Local Development Commands

Run Frappe console:

```bash
bench --site ledgix.local console
```

Run a Python import check:

```python
import ledgix_saas
```

Run migrations after app changes:

```bash
bench --site ledgix.local migrate
```

Build assets:

```bash
bench build
```

Watch assets during development:

```bash
bench watch
```

---

## App Source Location

Ledgix SaaS source app is stored in:

```text
apps/ledgix_saas/
```

During setup, it is copied or linked into:

```text
frappe-bench/apps/ledgix_saas/
```

Expected bench app path:

```text
pos/
└── frappe-bench/
    └── apps/
        └── ledgix_saas/
```

---

## App Installation Check

Use this checklist after creating a site:

```text
┌─────────────────────────────────────────────┬────────┐
│ Check                                       │ Status │
├─────────────────────────────────────────────┼────────┤
│ frappe-bench exists                         │   □    │
│ ledgix_saas exists in frappe-bench/apps     │   □    │
│ site exists in frappe-bench/sites           │   □    │
│ ledgix_saas is installed on site            │   □    │
│ migrate completed successfully              │   □    │
│ bench start is running                      │   □    │
│ site opens on port 8000                     │   □    │
└─────────────────────────────────────────────┴────────┘
```

---

## Troubleshooting

### Site Does Not Open

Check if bench is running:

```bash
cd frappe-bench
bench start
```

Check if port `8000` is already in use:

```bash
lsof -i :8000
```

---

### Site Name Does Not Resolve

Add local host entry:

```bash
sudo nano /etc/hosts
```

Add:

```text
127.0.0.1 ledgix.local
```

---

### Ledgix SaaS Not Installed

Check apps:

```bash
cd frappe-bench
bench --site ledgix.local list-apps
```

Install app manually:

```bash
bench --site ledgix.local install-app ledgix_saas
bench --site ledgix.local migrate
```

---

### Python Module Import Error

If you see:

```text
No module named ledgix_saas
```

Check app path:

```bash
ls frappe-bench/apps
```

Expected:

```text
ledgix_saas
```

Then from bench directory:

```bash
bench pip install -e apps/ledgix_saas
bench --site ledgix.local migrate
```

---

### Database Connection Issue

Check MariaDB service:

```bash
sudo systemctl status mariadb
```

Start MariaDB:

```bash
sudo systemctl start mariadb
```

---

### Redis Connection Issue

Check Redis service:

```bash
sudo systemctl status redis-server
```

Start Redis:

```bash
sudo systemctl start redis-server
```

---

### Assets Not Loading

Run:

```bash
cd frappe-bench
bench build
bench --site ledgix.local clear-cache
bench --site ledgix.local clear-website-cache
```

Then restart bench:

```bash
bench start
```

---

## Local Script Roles

```text
┌─────────────────┬────────────────────────────────────────┐
│ Script          │ Purpose                                │
├─────────────────┼────────────────────────────────────────┤
│ install.sh      │ Main setup launcher                     │
│ site_setup.sh   │ Site creation and Ledgix app install    │
│ start.sh        │ Local bench start/restart helper        │
└─────────────────┴────────────────────────────────────────┘
```

---

## Recommended Local Flow

```text
┌─────────────────────────────────────────────────────────────┐
│ Recommended First-Time Local Setup                          │
├─────────────────────────────────────────────────────────────┤
│ 1. git clone repo                                           │
│ 2. cd pos                                              │
│ 3. chmod +x install.sh site_setup.sh start.sh               │
│ 4. ./install.sh                                             │
│ 5. choose Local / Development Setup                         │
│ 6. ./site_setup.sh                                          │
│ 7. create ledgix.local                                      │
│ 8. install Ledgix SaaS                                      │
│ 9. ./start.sh                                               │
│ 10. open http://ledgix.local:8000                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Do Not Commit Local Files

The following should stay local:

```text
frappe-bench/
.env
*.env.local
*.log
*.sql.gz
*.tar
*.tgz
secrets.md
```

Before pushing:

```bash
git status
```

Only commit source code, scripts, docs, and safe configuration templates.

---

## Final Verification

After local setup, run:

```bash
cd frappe-bench
bench list-sites
bench --site ledgix.local list-apps
bench --site ledgix.local migrate
```

Expected installed apps:

```text
frappe
ledgix_saas
```

Then start:

```bash
bench start
```

Open:

```text
http://ledgix.local:8000
```

---

## Next Step

After local setup is working, use `docs/production/DEPLOYMENT.md` for production EC2/server deployment.
