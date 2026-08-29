# Apps Guide

> **Ledgix SaaS app structure, purpose, installation flow, and development notes.**

---

<div align="center">

# Ledgix SaaS

**The custom Frappe app included with Ledgix POS.**

</div>

---

## Overview

`Ledgix POS` currently includes one custom Frappe app:

```text id="0wbtwq"
ledgix_saas
```

The app is stored in:

```text id="5vhhlp"
apps/ledgix_saas/
```

During local or production setup, the app is copied or synced into the Frappe bench apps directory:

```text id="1e2e0v"
frappe-bench/apps/ledgix_saas/
```

Then it is installed on the required site using Bench.

---

## App Snapshot

```text id="xg3vxu"
┌─────────────────────────────────────────────────────────────┐
│                         Ledgix SaaS                         │
├─────────────────────────────────────────────────────────────┤
│ Framework      │ Frappe v15                                 │
│ App Name       │ ledgix_saas                                │
│ Source Path    │ apps/ledgix_saas                         │
│ Bench Path     │ frappe-bench/apps/ledgix_saas              │
│ Install Type   │ Per-site app installation                  │
│ Package File   │ pyproject.toml                             │
│ Hooks File     │ hooks.py                                   │
│ Modules File   │ modules.txt                                │
│ Patches File   │ patches.txt                                │
└─────────────────────────────────────────────────────────────┘
```

---

## App Directory Structure

```text id="25ngjv"
apps/ledgix_saas/
├── api/
├── config/
├── fixtures/
├── ledgix/
├── ledgix_saas/
│   └── setup/
├── ledgix_saas.egg-info/
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

---

## Directory Purpose

```text id="o5yx2b"
┌──────────────────────┬──────────────────────────────────────┐
│ Directory / File     │ Purpose                              │
├──────────────────────┼──────────────────────────────────────┤
│ api/                 │ Backend APIs and callable endpoints   │
│ config/              │ App configuration files               │
│ fixtures/            │ Exported records and setup data       │
│ ledgix/              │ Main app module / DocType logic       │
│ ledgix_saas/setup/   │ Setup helpers for Ledgix SaaS         │
│ patches/             │ Versioned database/app migrations     │
│ public/              │ Static assets                         │
│ setup/               │ Setup utilities                       │
│ templates/           │ Jinja templates                       │
│ www/                 │ Public web pages/routes               │
│ hooks.py             │ Frappe app hooks                      │
│ modules.txt          │ Frappe module list                    │
│ patches.txt          │ Patch execution list                  │
│ pyproject.toml       │ Python package metadata               │
└──────────────────────┴──────────────────────────────────────┘
```

---

## How Ledgix SaaS Fits Into Ledgix POS

```text id="2bxqnj"
┌──────────────────────────────┐
│ Ledgix POS Repository          │
└───────────────┬──────────────┘
                │
                ▼
┌──────────────────────────────┐
│ apps/ledgix_saas           │
│ Source app stored in repo     │
└───────────────┬──────────────┘
                │
                ▼
┌──────────────────────────────┐
│ frappe-bench/apps/ledgix_saas│
│ App copied/synced to bench    │
└───────────────┬──────────────┘
                │
                ▼
┌──────────────────────────────┐
│ Frappe Site                  │
│ App installed per site        │
└───────────────┬──────────────┘
                │
                ▼
┌──────────────────────────────┐
│ Ledgix SaaS Desk / Workflows │
└──────────────────────────────┘
```

---

## Installation Model

Ledgix SaaS is installed **per site**, not globally for every site automatically.

This means one bench can have multiple sites, and each site can decide whether to install Ledgix SaaS.

```text id="6m8vtu"
┌─────────────────────┬─────────────────────┐
│ Site                │ Installed App        │
├─────────────────────┼─────────────────────┤
│ ledgix.local        │ ledgix_saas          │
│ demo.local          │ ledgix_saas          │
│ test.local          │ Optional             │
└─────────────────────┴─────────────────────┘
```

Manual installation:

```bash id="701n53"
cd frappe-bench
bench --site ledgix.local install-app ledgix_saas
bench --site ledgix.local migrate
```

Check installed apps:

```bash id="pufsbj"
bench --site ledgix.local list-apps
```

Expected:

```text id="dd2ua5"
frappe
ledgix_saas
```

---

## App Lifecycle

```text id="gpi65r"
┌──────────────┐
│ Source App   │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Copy to Bench│
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Install App  │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Run Migrate  │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Clear Cache  │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Use in Desk  │
└──────────────┘
```

---

## Development Flow

When making changes to Ledgix SaaS:

```text id="z7sgms"
┌──────────────────────┐
│ Edit App Files       │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Run Migrations       │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Build Assets         │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Clear Cache          │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Restart Bench        │
└──────────────────────┘
```

Commands:

```bash id="1tyo92"
cd frappe-bench
bench --site ledgix.local migrate
bench build
bench --site ledgix.local clear-cache
bench --site ledgix.local clear-website-cache
bench restart
```

For local dev runner:

```bash id="wyf6nl"
bench start
```

---

## Important App Files

### hooks.py

`hooks.py` connects the app with Frappe.

It can define app metadata, fixtures, scheduled jobs, boot session hooks, document events, website settings, permissions, and other app-level behavior.

Check location:

```text id="f4n7a3"
apps/ledgix_saas/hooks.py
```

---

### modules.txt

`modules.txt` tells Frappe which modules are included in the app.

Check location:

```text id="0tj2i1"
apps/ledgix_saas/modules.txt
```

---

### patches.txt

`patches.txt` lists app patches that should run during migration.

Check location:

```text id="ns2iwf"
apps/ledgix_saas/patches.txt
```

Run patches through:

```bash id="5f5a51"
bench --site ledgix.local migrate
```

---

### pyproject.toml

`pyproject.toml` defines Python package metadata for the app.

Check location:

```text id="b8q3yb"
apps/ledgix_saas/pyproject.toml
```

Install package manually if required:

```bash id="d1awbh"
cd frappe-bench
bench pip install -e apps/ledgix_saas
```

---

## Fixtures

Fixtures are exported records used to recreate app configuration.

Common fixture examples:

```text id="ledht4"
- Custom Role
- Workspace
- Property Setter
- Custom Field
- Client Script
- Print Format
- Workflow
- Report
```

Export fixtures:

```bash id="kdqrah"
cd frappe-bench
bench --site ledgix.local export-fixtures
```

Then review files inside:

```text id="l4czup"
frappe-bench/apps/ledgix_saas/fixtures/
```

---

## Patches

Patches are used for controlled database or configuration changes.

Example patch flow:

```text id="h6skke"
┌──────────────────────┐
│ Create patch file    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Add path to patches.txt│
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Run bench migrate    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Patch executes once  │
└──────────────────────┘
```

Run patches:

```bash id="jldjgx"
bench --site ledgix.local migrate
```

---

## Public Assets and Web Pages

Static assets are stored in:

```text id="exugft"
public/
```

Website routes/pages are stored in:

```text id="mdpwwj"
www/
```

Templates are stored in:

```text id="pibbea"
templates/
```

Typical use:

```text id="q5sy3c"
┌──────────────────────┬────────────────────────────────────┐
│ Folder               │ Use                                │
├──────────────────────┼────────────────────────────────────┤
│ public/              │ CSS, JS, images, static assets      │
│ templates/           │ Jinja templates                     │
│ www/                 │ Public website pages/routes         │
└──────────────────────┴────────────────────────────────────┘
```

---

## API Layer

API-related code is stored in:

```text id="4skz39"
api/
```

Typical use cases:

```text id="kxgpb8"
┌──────────────────────┬────────────────────────────────────┐
│ API Use Case         │ Description                        │
├──────────────────────┼────────────────────────────────────┤
│ App endpoints        │ Python whitelisted methods          │
│ Integrations         │ External/internal integrations      │
│ Utility functions    │ Shared backend helpers              │
│ Automation           │ Programmatic app operations          │
└──────────────────────┴────────────────────────────────────┘
```

---

## Local App Verification

After setup, verify:

```bash id="mxz1x3"
cd frappe-bench
ls apps
bench --site ledgix.local list-apps
bench --site ledgix.local migrate
```

Expected app folder:

```text id="fb75lh"
apps/ledgix_saas
```

Expected installed apps:

```text id="38use5"
frappe
ledgix_saas
```

---

## Import Test

Open console:

```bash id="52w1du"
cd frappe-bench
bench --site ledgix.local console
```

Run:

```python id="a3900v"
import ledgix_saas
```

If no error appears, the Python package is importable.

---

## Common App Issues

```text id="b1tfhn"
┌───────────────────────────────┬────────────────────────────────────┐
│ Issue                         │ Fix / Check                        │
├───────────────────────────────┼────────────────────────────────────┤
│ App not found                 │ Check frappe-bench/apps folder      │
│ Module import error           │ bench pip install -e apps/app_name  │
│ App not installed on site     │ bench --site site install-app app   │
│ Fixtures not applying         │ Check hooks.py fixture config       │
│ Patch not running             │ Check patches.txt path              │
│ Desk not showing changes      │ clear-cache and migrate             │
│ Assets not updated            │ bench build                         │
└───────────────────────────────┴────────────────────────────────────┘
```

---

## Manual Recovery Commands

If the app exists but is not importable:

```bash id="wrgnwj"
cd frappe-bench
bench pip install -e apps/ledgix_saas
```

If the app exists but is not installed on the site:

```bash id="8rryst"
bench --site ledgix.local install-app ledgix_saas
bench --site ledgix.local migrate
```

If app changes are not visible:

```bash id="kgtvpc"
bench --site ledgix.local clear-cache
bench --site ledgix.local clear-website-cache
bench build
bench restart
```

---

## Recommended App Development Checklist

```text id="mi26ad"
┌──────────────────────────────────────────────┬────────┐
│ Check                                        │ Status │
├──────────────────────────────────────────────┼────────┤
│ App exists in apps/ledgix_saas             │   □    │
│ App copied to frappe-bench/apps/ledgix_saas  │   □    │
│ pyproject.toml exists                        │   □    │
│ hooks.py exists                              │   □    │
│ modules.txt exists                           │   □    │
│ patches.txt exists                           │   □    │
│ App installed on target site                 │   □    │
│ Migration completed                          │   □    │
│ Cache cleared                                │   □    │
│ Assets built if needed                       │   □    │
└──────────────────────────────────────────────┴────────┘
```

---

## Recommended Commit Flow for App Changes

```text id="1b5cip"
┌──────────────────────┐
│ Edit Ledgix App      │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Test Locally         │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Run Migration        │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Check Git Status     │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Commit Safe Files    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Push to GitHub       │
└──────────────────────┘
```

Commands:

```bash id="myl5ux"
git status
git add .
git commit -m "Update Ledgix SaaS app"
git push
```

Before pushing, make sure secrets and generated bench files are not included.

---

## Files That Should Not Be Committed

```text id="jgg924"
┌───────────────────────────────┬────────────────────────────────────┐
│ File / Folder                 │ Reason                             │
├───────────────────────────────┼────────────────────────────────────┤
│ frappe-bench/                 │ Generated local/production bench    │
│ .env                          │ Secrets/environment values          │
│ *.env.local                   │ Local secrets                       │
│ *.log                         │ Runtime logs                        │
│ *.sql.gz                      │ Database backups                    │
│ *.tar / *.tgz                 │ Backup archives                     │
│ secrets.md                    │ Private credentials                 │
│ deploy/production.secrets.md  │ Production credentials              │
└───────────────────────────────┴────────────────────────────────────┘
```

---

## Related Documentation

```text id="kbpk7l"
┌────────────────────────┬────────────────────────────────────┐
│ File                   │ Purpose                            │
├────────────────────────┼────────────────────────────────────┤
│ README.md              │ Project overview and quick start    │
│ docs/local/LOCAL_INSTALLATION.md  │ Local setup guide                   │
│ docs/production/DEPLOYMENT.md          │ Production deployment guide         │
│ docs/apps/APPS.md                │ Ledgix SaaS app details             │
│ docs/commands/COMMANDS.md            │ Useful terminal and bench commands  │
└────────────────────────┴────────────────────────────────────┘
```

---

## Final Note

Ledgix SaaS should always be tested after installation, migration, fixture export/import, and production deployment.

Minimum verification:

```bash id="q2dalu"
cd frappe-bench
bench --site ledgix.local list-apps
bench --site ledgix.local migrate
bench --site ledgix.local clear-cache
```

Expected:

```text id="6sqc3m"
frappe
ledgix_saas
```
