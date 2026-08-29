# Production Deployment Guide

> **Production server / EC2 deployment guide for Ledgix POS and Ledgix SaaS.**

---

<div align="center">

# Ledgix POS Production Deployment

**Server setup. Domain. SSL. Supervisor. Nginx. Backups. Updates.**

</div>

---

## Overview

This guide explains how to deploy **Ledgix SaaS** using the **Ledgix POS** repository on a production server.

Production deployment is different from local development.

Local development uses:

```text
bench start
```

Production uses:

```text
Nginx + Supervisor + Redis + MariaDB
```

---

## Production Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                         Internet                            │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                          Domain                             │
│                  erp.yourdomain.com                         │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                           Nginx                             │
│              Handles HTTP / HTTPS traffic                   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                       Frappe Bench                          │
│             Gunicorn + Socket.IO + Workers                  │
└──────────────────────────────┬──────────────────────────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        ▼                      ▼                      ▼
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│  MariaDB     │       │    Redis     │       │  File System │
│  Database    │       │ Cache/Queue  │       │ Sites/Assets │
└──────────────┘       └──────────────┘       └──────────────┘
```

---

## Production Flow

```text
┌──────────────────────┐
│ 1. Prepare Server    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 2. Point Domain DNS  │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 3. Clone Repository  │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 4. Run Production    │
│    Setup             │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 5. Create Site       │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 6. Install Ledgix    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 7. Enable Nginx      │
│    + Supervisor      │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 8. Enable SSL        │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 9. Verify Live Site  │
└──────────────────────┘
```

---

## Server Requirements

```text
┌─────────────────────┬────────────────────────────────────┐
│ Requirement         │ Recommended                        │
├─────────────────────┼────────────────────────────────────┤
│ OS                  │ Ubuntu Server                      │
│ Access              │ SSH with sudo user                 │
│ RAM                 │ 2 GB minimum, 4 GB+ recommended    │
│ CPU                 │ 2 vCPU recommended                 │
│ Storage             │ 20 GB+ recommended                 │
│ Domain              │ Required for SSL/live deployment   │
│ Database            │ MariaDB                            │
│ Cache/Queue         │ Redis                              │
│ Web Server          │ Nginx                              │
│ Process Manager     │ Supervisor                         │
└─────────────────────┴────────────────────────────────────┘
```

---

## Production vs Local

```text
┌─────────────────────┬─────────────────────┬─────────────────────┐
│ Area                │ Local Development   │ Production Server   │
├─────────────────────┼─────────────────────┼─────────────────────┤
│ Runner              │ bench start         │ Supervisor          │
│ Web Server          │ Bench dev server    │ Nginx               │
│ Port                │ 8000                │ 80 / 443            │
│ SSL                 │ Not required        │ Required            │
│ Domain              │ Optional            │ Required            │
│ Logs                │ Terminal/log files  │ Supervisor/Nginx    │
│ Use Case            │ Development/testing │ Live ERP system     │
└─────────────────────┴─────────────────────┴─────────────────────┘
```

---

## Step 1: Connect to Server

SSH into your server:

```bash
ssh user@your-server-ip
```

Example:

```bash
ssh ubuntu@123.123.123.123
```

Update packages:

```bash
sudo apt update && sudo apt upgrade -y
```

---

## Step 2: Point Domain to Server

Before SSL setup, point your domain/subdomain to the server IP.

Example DNS record:

```text
┌────────────┬──────────────────────┬────────────────────┐
│ Type       │ Name                 │ Value              │
├────────────┼──────────────────────┼────────────────────┤
│ A          │ erp                  │ YOUR_SERVER_IP     │
└────────────┴──────────────────────┴────────────────────┘
```

Example final domain:

```text
erp.yourdomain.com
```

Check DNS:

```bash
ping erp.yourdomain.com
```

Or:

```bash
nslookup erp.yourdomain.com
```

The domain should resolve to your server IP.

---

## Step 3: Clone Repository

```bash
git clone https://github.com/mshahwaiz-ali/pos.git
cd pos
```

Make scripts executable:

```bash
chmod +x install.sh site_setup.sh start.sh
chmod +x deploy/*.sh
```

---

## Step 4: Run Production Setup

Run the main installer:

```bash
./install.sh
```

Choose:

```text
2) Production / Server Setup
```

Or run the production setup directly:

```bash
deploy/production_setup.sh
```

---

## Step 5: Production Scripts

Production scripts are located inside:

```text
deploy/
```

```text
┌──────────────────────┬─────────────────────────────────────┐
│ Script               │ Purpose                             │
├──────────────────────┼─────────────────────────────────────┤
│ production_setup.sh  │ Main production setup script         │
│ deploy_update.sh     │ Pull/update/deploy latest changes    │
│ backup.sh            │ Create backups                       │
│ status.sh            │ Check production service status      │
│ docs/production/DEPLOYMENT.md │ Production deployment guide               │
└──────────────────────┴─────────────────────────────────────┘
```

---

## Step 6: Create Production Site

Production site name should usually match the real domain.

Example:

```text
erp.yourdomain.com
```

If using bench manually:

```bash
cd frappe-bench
bench new-site erp.yourdomain.com
```

Install Ledgix SaaS:

```bash
bench --site erp.yourdomain.com install-app ledgix_saas
bench --site erp.yourdomain.com migrate
```

Check installed apps:

```bash
bench --site erp.yourdomain.com list-apps
```

Expected:

```text
frappe
ledgix_saas
```

---

## Step 7: Setup Production Mode

From inside bench:

```bash
cd frappe-bench
sudo bench setup production $USER
```

This prepares Supervisor and Nginx configuration for production usage.

After setup, reload services:

```bash
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl restart all
sudo nginx -t
sudo systemctl reload nginx
```

---

## Step 8: Enable Scheduler

For ERP background jobs, enable scheduler:

```bash
cd frappe-bench
bench --site erp.yourdomain.com enable-scheduler
bench --site erp.yourdomain.com scheduler status
```

---

## Step 9: Enable SSL

After DNS is correctly pointing to the server:

```bash
cd frappe-bench
sudo bench setup lets-encrypt erp.yourdomain.com
```

Then verify:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Open:

```text
https://erp.yourdomain.com
```

---

## Step 10: Verify Services

Check Supervisor:

```bash
sudo supervisorctl status
```

Expected services include:

```text
frappe-bench-web
frappe-bench-workers
```

Check Nginx:

```bash
sudo nginx -t
sudo systemctl status nginx
```

Check MariaDB:

```bash
sudo systemctl status mariadb
```

Check Redis:

```bash
sudo systemctl status redis-server
```

---

## Production Health Check

```text
┌───────────────────────────────┬─────────────────────────────┐
│ Check                         │ Command                     │
├───────────────────────────────┼─────────────────────────────┤
│ Supervisor status             │ sudo supervisorctl status    │
│ Nginx config                  │ sudo nginx -t               │
│ Nginx service                 │ systemctl status nginx       │
│ MariaDB service               │ systemctl status mariadb     │
│ Redis service                 │ systemctl status redis-server│
│ Site apps                     │ bench --site site list-apps  │
│ Site migration                │ bench --site site migrate    │
│ Scheduler                     │ bench --site site scheduler status │
└───────────────────────────────┴─────────────────────────────┘
```

---

## Deployment Update Flow

When new changes are pushed to GitHub, update production with:

```bash
cd pos
git pull
```

Then run:

```bash
deploy/deploy_update.sh
```

Manual update flow:

```bash
cd frappe-bench
bench --site erp.yourdomain.com maintenance-mode on
bench --site erp.yourdomain.com migrate
bench build
sudo supervisorctl restart all
sudo systemctl reload nginx
bench --site erp.yourdomain.com maintenance-mode off
```

---

## Backup Flow

Run backup helper:

```bash
deploy/backup.sh
```

Manual backup:

```bash
cd frappe-bench
bench --site erp.yourdomain.com backup --with-files
```

Backups are usually stored under:

```text
frappe-bench/sites/erp.yourdomain.com/private/backups/
```

Recommended backup policy:

```text
┌──────────────────────┬────────────────────────────────────┐
│ Backup Type          │ Recommended Frequency              │
├──────────────────────┼────────────────────────────────────┤
│ Database             │ Daily                              │
│ Private files        │ Daily                              │
│ Public files         │ Daily                              │
│ Full server snapshot │ Weekly                             │
│ Before deployment    │ Every production update            │
└──────────────────────┴────────────────────────────────────┘
```

---

## Restore Flow

Move backup files to the site backups folder, then run:

```bash
cd frappe-bench
bench --site erp.yourdomain.com restore path/to/database.sql.gz
```

If restoring with files, restore public/private files according to Frappe backup output.

After restore:

```bash
bench --site erp.yourdomain.com migrate
bench --site erp.yourdomain.com clear-cache
sudo supervisorctl restart all
```

---

## Production Logs

Useful logs:

```text
┌─────────────────────┬──────────────────────────────────────┐
│ Log Type            │ Location / Command                   │
├─────────────────────┼──────────────────────────────────────┤
│ Supervisor status   │ sudo supervisorctl status             │
│ Web logs            │ frappe-bench/logs/web.log             │
│ Worker logs         │ frappe-bench/logs/worker.log          │
│ Scheduler logs      │ frappe-bench/logs/schedule.log        │
│ Nginx access logs   │ /var/log/nginx/access.log             │
│ Nginx error logs    │ /var/log/nginx/error.log              │
│ MariaDB logs        │ journalctl -u mariadb                 │
│ Redis logs          │ journalctl -u redis-server            │
└─────────────────────┴──────────────────────────────────────┘
```

View logs:

```bash
tail -f frappe-bench/logs/web.log
```

```bash
sudo tail -f /var/log/nginx/error.log
```

```bash
journalctl -u mariadb -f
```

```bash
journalctl -u redis-server -f
```

---

## Production Security Checklist

```text
┌──────────────────────────────────────────────┬────────┐
│ Security Check                               │ Status │
├──────────────────────────────────────────────┼────────┤
│ Domain points to server                      │   □    │
│ HTTPS enabled                                │   □    │
│ Root SSH login disabled if required          │   □    │
│ Administrator password entered/generated     │   □    │
│ Site DB password entered/generated and saved │   □    │
│ Secrets not committed to Git                 │   □    │
│ Backups enabled                              │   □    │
│ Firewall allows only required ports          │   □    │
│ Supervisor services running                  │   □    │
│ Nginx config tested                          │   □    │
└──────────────────────────────────────────────┴────────┘
```

Recommended open ports:

```text
┌────────┬──────────────┬──────────────────────────┐
│ Port   │ Service      │ Purpose                  │
├────────┼──────────────┼──────────────────────────┤
│ 22     │ SSH          │ Server access            │
│ 80     │ HTTP         │ Web / SSL challenge      │
│ 443    │ HTTPS        │ Secure web access        │
└────────┴──────────────┴──────────────────────────┘
```

---

## Do Not Use in Production

Do not use this as production process manager:

```bash
./start.sh
```

Do not rely on:

```bash
bench start
```

for a live server.

Production should run through:

```text
Supervisor + Nginx
```

---

## Production Troubleshooting

### Nginx Welcome Page Showing

Check enabled site config:

```bash
sudo nginx -t
ls -la /etc/nginx/sites-enabled/
```

Reload Nginx:

```bash
sudo systemctl reload nginx
```

---

### Site Not Opening

Check services:

```bash
sudo supervisorctl status
sudo nginx -t
sudo systemctl status nginx
```

Check bench logs:

```bash
tail -f frappe-bench/logs/web.log
```

---

### SSL Failed

Confirm DNS first:

```bash
ping erp.yourdomain.com
```

Then retry:

```bash
cd frappe-bench
sudo bench setup lets-encrypt erp.yourdomain.com
```

---

### App Not Installed

Check:

```bash
cd frappe-bench
bench --site erp.yourdomain.com list-apps
```

Install:

```bash
bench --site erp.yourdomain.com install-app ledgix_saas
bench --site erp.yourdomain.com migrate
```

---

### Supervisor Services Not Running

Run:

```bash
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl restart all
sudo supervisorctl status
```

---

### Redis Issue

Check Redis:

```bash
sudo systemctl status redis-server
```

Restart:

```bash
sudo systemctl restart redis-server
sudo supervisorctl restart all
```

---

### MariaDB Issue

Check MariaDB:

```bash
sudo systemctl status mariadb
```

Restart:

```bash
sudo systemctl restart mariadb
sudo supervisorctl restart all
```

---

## Production Maintenance Mode

Enable maintenance:

```bash
cd frappe-bench
bench --site erp.yourdomain.com maintenance-mode on
```

Disable maintenance:

```bash
bench --site erp.yourdomain.com maintenance-mode off
```

Check current config:

```bash
bench --site erp.yourdomain.com show-config
```

---

## Final Verification

After production setup, verify:

```bash
cd frappe-bench
bench --site erp.yourdomain.com list-apps
bench --site erp.yourdomain.com migrate
bench --site erp.yourdomain.com scheduler status
sudo supervisorctl status
sudo nginx -t
```

Expected installed apps:

```text
frappe
ledgix_saas
```

Open:

```text
https://erp.yourdomain.com
```

---

## Recommended Production Routine

```text
┌─────────────────────────────────────────────────────────────┐
│ Recommended Production Routine                              │
├─────────────────────────────────────────────────────────────┤
│ 1. Take backup before every update                          │
│ 2. Pull latest repo changes                                  │
│ 3. Run migration                                             │
│ 4. Build assets if frontend/static files changed             │
│ 5. Restart Supervisor services                               │
│ 6. Reload Nginx                                              │
│ 7. Check status.sh                                           │
│ 8. Test login and main workflows                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Related Files

```text
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

Production deployment should be handled carefully.

Always verify domain, backups, secrets, Supervisor, Nginx, MariaDB, Redis, and SSL before using the site as a live ERP system.
