# Commands Guide

> **Useful terminal, Bench CLI, Frappe, MariaDB, Redis, Nginx, Supervisor, logs, backup, restore, and troubleshooting commands for Ledgix POS and Ledgix SaaS.**

---

<div align="center">

# Ledgix POS Commands Handbook

**Bench. Sites. Apps. Database. Redis. Nginx. Supervisor. Logs. Fixes.**

</div>

---

## Overview

This file contains practical commands commonly needed while working with **Ledgix POS**, **Frappe Bench**, and **Ledgix SaaS**.

Use this guide for:

* Local development
* Site management
* App installation
* Bench start/restart issues
* Database operations
* Redis checks
* Production service checks
* Nginx and Supervisor troubleshooting
* Backups and restores
* Logs and debugging

---

## Quick Command Map

```text
┌────────────────────────┬────────────────────────────────────┐
│ Area                   │ Main Commands                      │
├────────────────────────┼────────────────────────────────────┤
│ Bench                  │ bench start, bench restart          │
│ Site                   │ new-site, list-sites, drop-site     │
│ App                    │ install-app, remove-app, list-apps  │
│ Migration              │ migrate, reload-doc                 │
│ Cache                  │ clear-cache, clear-website-cache    │
│ Database               │ mariadb, mysql, backup, restore     │
│ Redis                  │ systemctl status redis-server       │
│ Nginx                  │ nginx -t, systemctl reload nginx    │
│ Supervisor             │ supervisorctl status/restart        │
│ Logs                   │ tail -f logs/*.log                  │
│ Ports                  │ lsof -i :PORT                       │
└────────────────────────┴────────────────────────────────────┘
```

---

## Project Paths

```text
┌─────────────────────────────┬────────────────────────────────────┐
│ Path                        │ Purpose                            │
├─────────────────────────────┼────────────────────────────────────┤
│ pos/                   │ Main repository                    │
│ pos/frappe-bench/      │ Generated Frappe bench             │
│ frappe-bench/apps/          │ Installed bench apps               │
│ frappe-bench/sites/         │ Sites folder                       │
│ apps/ledgix_saas/         │ Source Ledgix SaaS app             │
│ deploy/                     │ Production helper scripts          │
│ env/                        │ Environment examples               │
└─────────────────────────────┴────────────────────────────────────┘
```

Go to project root:

```bash
cd pos
```

Go to bench:

```bash
cd pos/frappe-bench
```

---

# 1. Git Commands

## Check Git Status

```bash
git status
```

## Add Changes

```bash
git add .
```

## Commit Changes

```bash
git commit -m "Update documentation"
```

## Push Changes

```bash
git push
```

## Pull Latest Changes

```bash
git pull
```

## Check Remote Repo

```bash
git remote -v
```

## Fix Git Private Email Push Error

If GitHub blocks push due to private email:

```bash
git config user.email "YOUR_GITHUB_NOREPLY_EMAIL"
```

Example format:

```text
12345678+username@users.noreply.github.com
```

Then amend last commit:

```bash
git commit --amend --reset-author
git push
```

---

# 2. Bench Basic Commands

## Check Bench Version

```bash
bench --version
```

## Start Bench Locally

```bash
cd frappe-bench
bench start
```

## Restart Bench

```bash
cd frappe-bench
bench restart
```

## Build Assets

```bash
cd frappe-bench
bench build
```

## Update Bench

```bash
cd frappe-bench
bench update
```

## Check Bench Config

```bash
cd frappe-bench
bench config
```

## Show Bench Help

```bash
bench --help
```

---

# 3. Site Commands

## List Sites

```bash
cd frappe-bench
bench list-sites
```

## Create New Site

```bash
cd frappe-bench
bench new-site ledgix.local
```

## Drop Site

```bash
cd frappe-bench
bench drop-site ledgix.local --force
```

## Set Default Site

```bash
cd frappe-bench
bench use ledgix.local
```

## Check Current Default Site

```bash
cd frappe-bench
cat sites/currentsite.txt
```

## Manually Set Current Site

```bash
cd frappe-bench
echo "ledgix.local" > sites/currentsite.txt
```

## Open Site Console

```bash
cd frappe-bench
bench --site ledgix.local console
```

## Open MariaDB Console for Site

```bash
cd frappe-bench
bench --site ledgix.local mariadb
```

## Open Frappe Shell

```bash
cd frappe-bench
bench --site ledgix.local console
```

---

# 4. App Commands

## List Bench Apps

```bash
cd frappe-bench
ls apps
```

## List Apps Installed on Site

```bash
cd frappe-bench
bench --site ledgix.local list-apps
```

Expected:

```text
frappe
ledgix_saas
```

## Install Ledgix SaaS on Site

```bash
cd frappe-bench
bench --site ledgix.local install-app ledgix_saas
```

## Remove App from Site

```bash
cd frappe-bench
bench --site ledgix.local remove-app ledgix_saas
```

## Install App Package in Editable Mode

```bash
cd frappe-bench
bench pip install -e apps/ledgix_saas
```

## Test Python Import

```bash
cd frappe-bench
bench --site ledgix.local console
```

Inside console:

```python
import ledgix_saas
```

---

# 5. Migration and Cache Commands

## Run Migration

```bash
cd frappe-bench
bench --site ledgix.local migrate
```

## Clear Cache

```bash
cd frappe-bench
bench --site ledgix.local clear-cache
```

## Clear Website Cache

```bash
cd frappe-bench
bench --site ledgix.local clear-website-cache
```

## Clear All and Rebuild

```bash
cd frappe-bench
bench --site ledgix.local clear-cache
bench --site ledgix.local clear-website-cache
bench build
bench restart
```

## Reload Specific DocType

```bash
cd frappe-bench
bench --site ledgix.local reload-doc module_name doctype doctype_name
```

Example:

```bash
bench --site ledgix.local reload-doc ledgix doctype customer
```

---

# 6. Administrator Password Commands

## Change Administrator Password

```bash
cd frappe-bench
bench --site ledgix.local set-admin-password "NewStrongPassword"
```

## Reset User Password from Console

```bash
cd frappe-bench
bench --site ledgix.local console
```

Inside console:

```python
import frappe
user = frappe.get_doc("User", "user@example.com")
user.new_password = "NewStrongPassword"
user.save()
frappe.db.commit()
```

---

# 7. Database Commands

## Check MariaDB Status

```bash
sudo systemctl status mariadb
```

## Start MariaDB

```bash
sudo systemctl start mariadb
```

## Restart MariaDB

```bash
sudo systemctl restart mariadb
```

## Login to MariaDB as Root

```bash
sudo mariadb
```

Or:

```bash
sudo mysql
```

## Show Databases

```sql
SHOW DATABASES;
```

## Show Users

```sql
SELECT User, Host FROM mysql.user;
```

## Change MariaDB Root Password

Inside MariaDB:

```sql
ALTER USER 'root'@'localhost' IDENTIFIED BY 'NewStrongPassword';
FLUSH PRIVILEGES;
```

## Create Database User

Inside MariaDB:

```sql
CREATE USER 'frappe_admin'@'localhost' IDENTIFIED BY 'StrongPassword';
GRANT ALL PRIVILEGES ON *.* TO 'frappe_admin'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```

## Change Database User Password

Inside MariaDB:

```sql
ALTER USER 'frappe_admin'@'localhost' IDENTIFIED BY 'NewStrongPassword';
FLUSH PRIVILEGES;
```

## Check Site Database Name

```bash
cd frappe-bench
cat sites/ledgix.local/site_config.json
```

Look for:

```json
"db_name": "database_name"
```

## Open Site Database

```bash
cd frappe-bench
bench --site ledgix.local mariadb
```

## Show Tables

Inside site database:

```sql
SHOW TABLES;
```

## Check TabUser

```sql
SELECT name, enabled FROM tabUser;
```

---

# 8. Redis Commands

## Check Redis Status

```bash
sudo systemctl status redis-server
```

## Start Redis

```bash
sudo systemctl start redis-server
```

## Restart Redis

```bash
sudo systemctl restart redis-server
```

## Check Redis Port

```bash
redis-cli ping
```

Expected:

```text
PONG
```

## Check Redis Logs

```bash
journalctl -u redis-server -f
```

---

# 9. Supervisor Commands

Production uses Supervisor.

## Check Supervisor Status

```bash
sudo supervisorctl status
```

## Restart All Supervisor Processes

```bash
sudo supervisorctl restart all
```

## Reread Supervisor Config

```bash
sudo supervisorctl reread
```

## Update Supervisor Config

```bash
sudo supervisorctl update
```

## Restart Frappe Web Group

```bash
sudo supervisorctl restart frappe-bench-web:
```

## Restart Frappe Workers Group

```bash
sudo supervisorctl restart frappe-bench-workers:
```

## Check Supervisor Service

```bash
sudo systemctl status supervisor
```

## Restart Supervisor Service

```bash
sudo systemctl restart supervisor
```

---

# 10. Nginx Commands

## Test Nginx Config

```bash
sudo nginx -t
```

## Reload Nginx

```bash
sudo systemctl reload nginx
```

## Restart Nginx

```bash
sudo systemctl restart nginx
```

## Check Nginx Status

```bash
sudo systemctl status nginx
```

## Check Enabled Sites

```bash
ls -la /etc/nginx/sites-enabled/
```

## Check Available Sites

```bash
ls -la /etc/nginx/sites-available/
```

## View Nginx Error Log

```bash
sudo tail -f /var/log/nginx/error.log
```

## View Nginx Access Log

```bash
sudo tail -f /var/log/nginx/access.log
```

---

# 11. SSL Commands

## Setup Let's Encrypt SSL

```bash
cd frappe-bench
sudo bench setup lets-encrypt erp.yourdomain.com
```

## Check SSL Certificate

```bash
sudo certbot certificates
```

## Renew SSL

```bash
sudo certbot renew
```

## Dry Run SSL Renewal

```bash
sudo certbot renew --dry-run
```

---

# 12. Port Commands

## Check Port 8000

```bash
lsof -i :8000
```

## Check Port 9000

```bash
lsof -i :9000
```

## Check Redis Ports

```bash
lsof -i :11000
lsof -i :13000
```

## Kill Process on Port

```bash
kill -9 PID
```

Example:

```bash
kill -9 12345
```

## Kill Bench Processes

```bash
pkill -f "bench start"
```

## Kill Node Socket.IO Process

```bash
pkill -f "node.*socketio"
```

## Kill Frappe Processes

```bash
pkill -f frappe
```

Use process killing carefully. Check ports first.

---

# 13. Logs Commands

## Bench Logs Folder

```bash
cd frappe-bench
ls logs
```

## Watch Web Log

```bash
cd frappe-bench
tail -f logs/web.log
```

## Watch Worker Log

```bash
cd frappe-bench
tail -f logs/worker.log
```

## Watch Scheduler Log

```bash
cd frappe-bench
tail -f logs/schedule.log
```

## Watch Socket.IO Log

```bash
cd frappe-bench
tail -f logs/node-socketio.log
```

## Watch All Recent Logs

```bash
cd frappe-bench
tail -n 100 logs/*.log
```

---

# 14. Backup Commands

## Create Backup with Files

```bash
cd frappe-bench
bench --site ledgix.local backup --with-files
```

## Create Database Backup Only

```bash
cd frappe-bench
bench --site ledgix.local backup
```

## Find Backups

```bash
cd frappe-bench
ls sites/ledgix.local/private/backups/
```

## Production Backup Helper

```bash
cd pos
deploy/backup.sh
```

---

# 15. Restore Commands

## Restore Database

```bash
cd frappe-bench
bench --site ledgix.local restore path/to/database.sql.gz
```

## Restore Then Migrate

```bash
cd frappe-bench
bench --site ledgix.local restore path/to/database.sql.gz
bench --site ledgix.local migrate
bench --site ledgix.local clear-cache
```

## Restart After Restore

```bash
bench restart
```

Production:

```bash
sudo supervisorctl restart all
sudo systemctl reload nginx
```

---

# 16. Maintenance Mode

## Enable Maintenance Mode

```bash
cd frappe-bench
bench --site ledgix.local maintenance-mode on
```

## Disable Maintenance Mode

```bash
cd frappe-bench
bench --site ledgix.local maintenance-mode off
```

## Check Site Config

```bash
cd frappe-bench
bench --site ledgix.local show-config
```

---

# 17. Scheduler Commands

## Enable Scheduler

```bash
cd frappe-bench
bench --site ledgix.local enable-scheduler
```

## Disable Scheduler

```bash
cd frappe-bench
bench --site ledgix.local disable-scheduler
```

## Check Scheduler Status

```bash
cd frappe-bench
bench --site ledgix.local scheduler status
```

## Run Scheduler Once

```bash
cd frappe-bench
bench --site ledgix.local execute frappe.utils.scheduler.enqueue_scheduler_events
```

---

# 18. Developer Commands

## Open Bench Console

```bash
cd frappe-bench
bench --site ledgix.local console
```

## Execute Python Method

```bash
cd frappe-bench
bench --site ledgix.local execute path.to.method
```

Example:

```bash
bench --site ledgix.local execute ledgix_saas.setup.install.after_install
```

## Run Frappe Doctor

```bash
cd frappe-bench
bench doctor
```

## Run Python Compile Check

```bash
python3 -m py_compile path/to/file.py
```

## Find Python Files

```bash
find apps/ledgix_saas -name "*.py"
```

## Search Text in App

```bash
grep -R "search_text" apps/ledgix_saas
```

Example:

```bash
grep -R "doctype" apps/ledgix_saas
```

---

# 19. Asset Commands

## Build Assets

```bash
cd frappe-bench
bench build
```

## Watch Assets

```bash
cd frappe-bench
bench watch
```

## Clear Asset Cache

```bash
cd frappe-bench
bench --site ledgix.local clear-website-cache
bench build
```

---

# 20. Production Update Commands

## Standard Production Update

```bash
cd pos
git pull
deploy/deploy_update.sh
```

## Manual Production Update

```bash
cd pos
git pull
cd frappe-bench
bench --site erp.yourdomain.com maintenance-mode on
bench --site erp.yourdomain.com migrate
bench build
sudo supervisorctl restart all
sudo systemctl reload nginx
bench --site erp.yourdomain.com maintenance-mode off
```

---

# 21. Common Fixes

## Fix: App Exists But Not Importable

```bash
cd frappe-bench
bench pip install -e apps/ledgix_saas
bench --site ledgix.local migrate
```

## Fix: App Not Installed on Site

```bash
cd frappe-bench
bench --site ledgix.local install-app ledgix_saas
bench --site ledgix.local migrate
```

## Fix: Desk Changes Not Showing

```bash
cd frappe-bench
bench --site ledgix.local clear-cache
bench --site ledgix.local clear-website-cache
bench build
bench restart
```

## Fix: Site Not Opening Locally

```bash
cd frappe-bench
bench start
```

Check hosts file:

```bash
cat /etc/hosts
```

Add if missing:

```text
127.0.0.1 ledgix.local
```

## Fix: Port Already in Use

```bash
lsof -i :8000
kill -9 PID
```

## Fix: Redis Not Responding

```bash
sudo systemctl restart redis-server
redis-cli ping
```

## Fix: MariaDB Not Running

```bash
sudo systemctl restart mariadb
sudo systemctl status mariadb
```

## Fix: Production Nginx Issue

```bash
sudo nginx -t
sudo systemctl reload nginx
sudo tail -f /var/log/nginx/error.log
```

## Fix: Production Supervisor Issue

```bash
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl restart all
sudo supervisorctl status
```

---

# 22. Recommended Daily Local Flow

```text
┌─────────────────────────────────────────────────────────────┐
│ Daily Local Development Flow                                │
├─────────────────────────────────────────────────────────────┤
│ 1. cd pos                                              │
│ 2. git pull                                                 │
│ 3. cd frappe-bench                                          │
│ 4. bench --site ledgix.local migrate                        │
│ 5. bench --site ledgix.local clear-cache                    │
│ 6. bench start                                              │
└─────────────────────────────────────────────────────────────┘
```

Commands:

```bash
cd pos
git pull
cd frappe-bench
bench --site ledgix.local migrate
bench --site ledgix.local clear-cache
bench start
```

---

# 23. Recommended Production Flow

```text
┌─────────────────────────────────────────────────────────────┐
│ Safe Production Update Flow                                 │
├─────────────────────────────────────────────────────────────┤
│ 1. Take backup                                              │
│ 2. Pull latest code                                         │
│ 3. Enable maintenance mode                                  │
│ 4. Run migration                                            │
│ 5. Build assets                                             │
│ 6. Restart Supervisor                                       │
│ 7. Reload Nginx                                             │
│ 8. Disable maintenance mode                                 │
│ 9. Test live site                                           │
└─────────────────────────────────────────────────────────────┘
```

Commands:

```bash
cd pos
deploy/backup.sh
git pull
cd frappe-bench
bench --site erp.yourdomain.com maintenance-mode on
bench --site erp.yourdomain.com migrate
bench build
sudo supervisorctl restart all
sudo systemctl reload nginx
bench --site erp.yourdomain.com maintenance-mode off
```

---

# 24. Final Health Check

## Local Health Check

```bash
cd frappe-bench
bench list-sites
bench --site ledgix.local list-apps
bench --site ledgix.local migrate
bench doctor
```

## Production Health Check

```bash
cd frappe-bench
bench --site erp.yourdomain.com list-apps
bench --site erp.yourdomain.com migrate
bench --site erp.yourdomain.com scheduler status
sudo supervisorctl status
sudo nginx -t
sudo systemctl status nginx
sudo systemctl status mariadb
sudo systemctl status redis-server
```

---

## Final Note

Use commands carefully, especially database, restore, drop-site, kill process, and production restart commands.

For local development, prefer:

```bash
bench start
```

For production, prefer:

```bash
sudo supervisorctl restart all
sudo systemctl reload nginx
```
