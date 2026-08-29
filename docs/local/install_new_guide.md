Final Installer Plan
1. install.sh ka role clear

install.sh mein only ye hoga:

1) Local / Development Install
2) Production / Server Install
3) Exit
Local choose karne par
OS detect
WSL vs Native Linux detect
installed cheezen check
missing cheezen install
already installed compatible cheezen skip
incompatible cheezon ke liye user ko options
bench init/reuse/repair
apps copy/install-ready
site setup trigger option
secrets update
rollback on failure
Production choose karne par
bash deploy/production_setup.sh
Remove from install.sh

Ye sab nahi hoga:

Start Bench
Stop Bench
Status
Runtime menu
Expose/tunnel
Developer convenience commands

Ye start.sh ya separate helper scripts mein rahenge.

2. Installer mode flow
Start screen
ERP Prod Installer

Detected:
- OS: Ubuntu / Debian / WSL
- Environment: WSL2 / Native Linux
- Architecture: x86_64
- RAM: 16 GB
- Repo path: /path/to/pos

Choose install type:

1) Local / Development Install
2) Production / Server Install
3) Exit
3. Local install stages

Local install ko stages mein todna hai:

Stage 1: System detection
Stage 2: Preflight checks
Stage 3: Version selection
Stage 4: Dependency install/skip
Stage 5: MariaDB/Redis setup
Stage 6: Bench setup
Stage 7: Apps preparation
Stage 8: Site setup handoff
Stage 9: Secrets sync
Stage 10: Final verification
4. Idempotent install: already installed ho to skip

Har dependency ke liye rule:

Item	Check	Action
Git	command -v git	installed hai to skip
Curl	command -v curl	installed hai to skip
Python	python3 --version	compatible hai to skip
Node	node -v	compatible hai to skip/reuse option
Yarn/Corepack	yarn -v / corepack	installed hai to skip
MariaDB	mysql --version	installed + running check
Redis	redis-server --version	installed + running check
Bench	bench --version	installed hai to skip
Frappe bench folder	frappe-bench/ exists	reuse/repair/recreate prompt
Apps	apps/app_name exists	copy/install check
Site	frappe-bench/sites/site.local exists	skip/repair/delete prompt

Example output:

Preflight check:

git              installed
curl             installed
python3          3.12.13 - compatible
node             22.18.0 - compatible
yarn             missing
mariadb          installed
redis            installed
frappe-bench     exists
bench CLI        installed

Installer will install:
- yarn/corepack

Installer will skip:
- git
- curl
- python3
- node
- mariadb
- redis
- bench folder

This is the correct behavior.

5. Version selection system

Installer should not force versions blindly.

Node selection

Recommended logic:

Node.js options:

Detected:
- Installed Node: 22.x
- Recommended for this system: Node 22 LTS
- Available choices:
  1) Use installed Node 22.x  [Recommended]
  2) Install Node 22 LTS
  3) Install Node 24
  4) Manual version
Rule
If Node 22 is installed and compatible: reuse.
If no Node installed: recommend Node 22 LTS.
If Node 24 fails or unsupported: fallback to Node 22.
Node 24 should not be hard-forced.

For Frappe v15, Node 18/20/22/24 cases can vary depending on OS and package source, so this user-choice model is safer than hardcoding.

Python selection
Python options:

Detected:
- System Python: 3.12.x
- Recommended: Use system Python 3.12

1) Use installed Python 3.12  [Recommended]
2) Install Python 3.12 packages
3) Manual
Yarn/Corepack selection

Instead of forcing global Yarn blindly:

Yarn setup:

1) Enable Corepack and prepare Yarn 1.x  [Recommended]
2) Install Yarn globally with npm
3) Use existing Yarn

Recommended: Corepack first, npm global fallback.

6. WSL handling

WSL ko separate first-class path banana hoga.

Detect
grep -qi microsoft /proc/version

or:

grep -qi wsl /proc/sys/kernel/osrelease
WSL choices
WSL detected.

Choose local environment mode:

1) WSL / Windows laptop setup  [Recommended]
2) Native Linux setup
WSL-specific behavior
A. systemctl fallback

Native Linux:

sudo systemctl enable --now mariadb
sudo systemctl enable --now redis-server

WSL fallback:

sudo service mysql start
sudo service redis-server start
B. Hosts file

For Linux /etc/hosts:

127.0.0.1 site.local

For Windows browser access, WSL needs Windows hosts entry too:

127.0.0.1 site.local

But installer should not silently edit Windows hosts.

Options:

WSL browser access setup:

1) Add Linux /etc/hosts only
2) Print Windows PowerShell command
3) Try Windows hosts update using powershell.exe
4) Skip hosts setup

Recommended: print command and ask user.

C. Final WSL URL message
Access from Windows:
http://localhost:8000

Custom domain:
http://site.local:8000
only after Windows hosts entry is added.
7. Secrets management

This is important.

We should create a proper secrets folder, for example:

.secrets/
  sites.env
  sites/
    millitrix.local.env
    ledgix.local.env

.secrets/ must be in .gitignore.

When site is created

Save credentials:

SITE_NAME=millitrix.local
SITE_URL=http://millitrix.local:8000
ADMIN_USER=Administrator
ADMIN_PASSWORD=generated_or_user_password
DB_NAME=_site_db_name
DB_PASSWORD=generated_db_password
CREATED_AT=2026-07-06T...
INSTALLED_APPS=frappe,millitrix,ledgix_saas
ENVIRONMENT=local-wsl
Default admin password

You said default admin password should be saved to secrets.

Better model:

Admin password:

1) Generate secure password  [Recommended]
2) Use default development password
3) Enter manually

For client/dev installs, default can be allowed, but generated is safer.

If default selected:

ADMIN_PASSWORD=admin

or your standard default.

When site is deleted

This was the confusion point. Fix:

When site_setup.sh or delete function removes a site:

bench drop-site site.local --force
rm -f .secrets/sites/site.local.env
remove site.local row from .secrets/sites.env
remove hosts entry if installer owns it / ask user

Installer must keep secrets synchronized with actual sites.

When script reruns

It should compare:

site exists in bench
site exists in .secrets
secrets exists but site missing
site exists but secrets missing

Then show:

Secrets consistency check:

- millitrix.local exists and secrets found
- oldsite.local secrets found but site missing

Clean stale secrets?
1) Yes
2) No

Recommended: yes.

8. Rollback design

Rollback should be careful. We should not uninstall user’s system packages automatically unless installer installed them in this run and user confirms.

Transaction log

During install, maintain:

logs/install/install-xxxx.actions

Example:

INSTALLED_PACKAGE git
INSTALLED_PACKAGE redis-server
CREATED_BENCH frappe-bench
CREATED_SITE millitrix.local
COPIED_APP millitrix
CREATED_SECRET .secrets/sites/millitrix.local.env
ADDED_HOST_ENTRY /etc/hosts millitrix.local
On failure

Prompt:

Installation failed at: bench init

Rollback options:
1) Rollback only files created by this run  [Recommended]
2) Rollback files + sites created by this run
3) Rollback everything installer created in this run
4) Keep everything for debugging
What rollback can safely remove

Safe:

partially created frappe-bench if created in this run
copied apps into bench if copied in this run
newly created site if created in this run
new secret file created in this run
temporary files
log markers

Careful / ask first:

apt packages
MariaDB server
Redis server
Node installation
existing bench
existing sites
existing secrets

Never silently delete:

existing apps
existing repo files
existing client data
existing database unless created in this run and confirmed
9. Bench handling

If frappe-bench/ already exists:

Existing bench found.

Choose:
1) Reuse existing bench  [Recommended]
2) Repair bench dependencies
3) Recreate bench
4) Cancel
Reuse check

Run checks:

bench --version
bench list-apps
test -f sites/apps.txt
Repair mode

Repair should:

reinstall Python requirements
run bench setup requirements
run bench build if needed
copy missing apps from apps
do not destroy sites
Recreate mode

Ask hard confirmation:

This will remove ./frappe-bench but not apps or repo source.
Type RECREATE to continue:
10. Apps preparation

apps/ remains source of truth.

Flow:

Available local apps:

1) millitrix
2) ledgix_saas

Prepare apps for bench?
1) Copy all apps
2) Select apps
3) Skip

For each app:

millitrix:
- source found in apps/millitrix
- destination missing in frappe-bench/apps/millitrix
Action: copy

ledgix_saas:
- destination exists
Action: skip/update prompt

If app has pyproject.toml or setup.py:

pip install -e apps/app_name

If not:

No pyproject/setup.py found. Copy-only app.
11. Site setup handoff

install.sh should not become too huge. Best architecture:

install.sh              main installer entry
scripts/common.sh       shared functions
scripts/local_setup.sh  local dependency + bench setup
site_setup.sh           create/delete/list sites + secrets sync
deploy/production_setup.sh

But if we want minimal repo change:

Keep install.sh as main.
Add helper functions inside it for now.
Update site_setup.sh separately.

At end of local install:

Local installer completed.

Next:
1) Create/manage sites now
2) Exit

If choose 1:

bash ./site_setup.sh
12. Site setup must also be fixed

Because secrets deletion issue belongs more in site_setup.sh.

Required site menu:

Site Setup

1) Create site
2) Delete site
3) List sites
4) Repair secrets
5) Back
Create site
ask site name
ask admin password strategy
ask apps to install
create site
install selected apps
migrate
save secrets
hosts setup
Delete site
select site
confirm
bench drop-site
remove secret file
remove from secrets index
ask about hosts cleanup
Repair secrets
remove stale secret entries
create missing secret stubs for existing sites if needed
show mismatches
13. What should be changed in install.sh first

Priority order:

Must-have changes
Top-level menu
Local
Production
Exit
Remove runtime menu
no start
no stop
no status
Preflight summary
detect installed tools
skip compatible installed packages
Version chooser
Node version menu
Python compatibility check
Yarn/Corepack option
WSL/native mode
service fallback
hosts warning
Windows browser instructions
Bench reuse/repair/recreate prompt
Failure rollback trap
action log
cleanup created files/sites/secrets
Secrets sync handoff
call site_setup.sh or fix within it later
14. Best professional behavior
Installer should be non-destructive by default

Default answers should be safe:

reuse existing bench
skip installed compatible packages
keep existing DB
keep existing sites
keep logs
do not modify Windows hosts silently
do not remove apt packages silently
Installer should be explicit before risky actions

Ask before:

deleting bench
deleting site
changing hosts
changing Node major version
resetting database
removing secrets
Installer should be resumable

If internet fails or Node install fails:

rerun script
preflight detects completed steps
continues from missing step
no duplicate work
Final proposed architecture
pos/
├── install.sh
├── site_setup.sh
├── start.sh
├── deploy/
│   └── production_setup.sh
├── apps/
│   ├── millitrix/
│   └── ledgix_saas/
├── .secrets/
│   ├── sites.env
│   └── sites/
│       └── site.local.env
└── logs/install/
    ├── install-xxxx.log
    └── install-xxxx.actions
My final recommendation

Best approach ye hai:

Step 1

Patch install.sh into a proper local/prod installer:

top-level menu
local/prod split
installed checks + skips
version chooser
WSL detection
bench reuse/repair/recreate
rollback trap
no start/stop/status
Step 2

Patch site_setup.sh:

create/delete/list sites
app selection per site
secrets create/delete/repair
WSL hosts guidance
Step 3

Test on 3 cases:

Case 1: Fresh Ubuntu
Case 2: Fresh WSL
Case 3: Rerun after partial install