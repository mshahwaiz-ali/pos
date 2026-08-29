Ledgix POS V2 — Revised Master Architecture & Implementation Plan

Status: Master implementation plan
Product direction: Frappe + Ledgix, retail-first POS with B2B capability, FBR compliance, multi-site SaaS readiness
Planning rule: This document defines the target architecture and implementation order. Small implementation details may change when code reality justifies it, but the core architecture and data-integrity rules should not drift without an explicit decision.

1. Executive Decision

Ledgix V2 should become a clean POS + back-office product, not a collection of custom dashboards and duplicate CRUD screens.

The final product should use:

Custom UI only where workflow speed or cross-document intelligence genuinely requires it

Native Frappe Workspace, Lists, Forms and Reports for standard back-office work

One authoritative backend for sales, stock, tax, payments, returns and FBR

Retail and B2B as two selling contexts on the same backend

Site-level configuration for each customer

No ERPNext dependency for Ledgix V2

No second permanent navigation system inside Frappe Desk

The final custom-page footprint remains intentionally small:

Ledgix POS

Tax & FBR Center

Inventory Intelligence

Everything else should use native Frappe unless a real workflow proves that native Frappe is insufficient.

2. Revision Highlights

Compared with the previous plan, the following changes are important.

2.1 Backend contracts move before the full POS rewrite

The POS UI must not be rebuilt against a data model that we already know will change.

Before the final POS V2 implementation, we should lock the core contracts for:

sale channel

pricing

payment handling

shifts

returns

tax snapshots

stock posting

B2B customer context

These should be additive migrations and should preserve current working behavior until the new UI is ready.

2.2 B2B receivables should use payments + allocations, not only a mutable balance

For a proper B2B implementation, a customer's outstanding balance should not depend on manually updating one number.

Recommended model:

Sale / Invoice
      │
      ├──── Return / Credit
      │
      └──── Payment Allocation
                  │
                  ▼
             Ledgix Payment

A payment may later be allocated to one or multiple invoices.

Customer:

Outstanding

Available Credit

Aging

Statement

should be derived from authoritative sales, returns and payment allocations.

A cached summary may exist for performance, but it should not be the source of truth.

2.3 Homepage routing is UX, not authorization

Examples:

Cashier → POS
Manager → Ledgix Workspace
Admin   → Ledgix Workspace

are correct for user experience.

But access control must still be enforced through:

DocType permissions

Page permissions

API/server-side authorization

role-aware actions

business rules

A cashier must not gain manager capability simply by manually opening another route.

2.4 Financial transactions become effectively immutable after posting

Once a Sale is finalized/submitted, historical truth must not change because somebody edits:

Item

Price List

Tax Profile

Customer

FBR settings

current stock settings

Corrections should happen through explicit transactions such as:

Sales Return

Credit adjustment

Payment reversal

Stock correction

authorized cancellation where legally/operationally allowed

This applies especially to:

price snapshots

discount snapshots

tax snapshots

notified retail price snapshots

buyer identity used on invoice

payment summary

FBR payload/submission history

2.5 Legacy pages follow a migration gate

No legacy page is deleted simply because the replacement looks better.

For each page/module:

Inventory current capability
        ↓
Map each capability to destination
        ↓
Implement replacement
        ↓
Test parity + permissions
        ↓
Update Workspace/navigation
        ↓
Delete old page/assets/routes

This is the rule for Operations Center, Reports Center, Quick Item Scan and old navigation.

3. Final Product Architecture

                              LEDGIX POS
                                  │
          ┌───────────────────────┼────────────────────────┐
          │                       │                        │
       SELLING                BACK OFFICE              COMPLIANCE
          │                       │                        │
   Custom POS Page        Frappe Workspace        Tax & FBR Center
          │                       │                        │
   Retail + B2B          Native Lists/Forms       Native Settings
          │               Native Reports          + Operations UI
          │                       │
          │               Inventory Intelligence
          │                  Custom Page
          │
          └────────────────── SAME BACKEND ──────────────────┘
                    │        │       │       │
                  Sales    Stock   Pricing   Tax/FBR
                    │        │       │       │
                    └──── Payments / Returns ────┘

4. Architectural Rule: UI Does Not Own Business Logic

The new UI should call stable backend services.

Recommended logical layers:

Custom Page / Frappe Form / Report
                │
                ▼
             API Layer
                │
                ▼
          Domain Services
                │
     ┌──────────┼───────────┐
     │          │           │
 Pricing      Sales       Payments
 Stock        Returns     Tax/FBR
                │
                ▼
             DocTypes

Important rule:

A page should not contain its own competing calculation of price, stock, tax, outstanding balance or FBR state.

Examples:

POS asks Pricing Service for the effective price.

POS asks Tax Service for the sale calculation.

Finalizing Sale calls Stock Service.

Payment posting calls Payment Service.

Return processing calls the same authoritative Sale/Stock/Tax domain logic.

Tax & FBR Center monitors or operates the same FBR service used by Sale.

This makes the app maintainable even if the UI changes again later.

5. Custom Page Decisions

Page

Decision

Final Role

Ledgix POS

🟢 Keep + full redesign

High-speed selling

Tax & FBR Center

🟢 Keep + simplify

Compliance operations

Inventory Intelligence

🟢 Keep + simplify

Cross-document inventory analysis

Current Dashboard

🔴 Delete

Replaced by Workspace

Operations Center

🔴 Delete after parity

Replaced by native Lists/Forms

Reports Center

🔴 Delete after report migration

Replaced by native Reports

Quick Item Scan

🔴 Delete after integration

Barcode functionality moves to POS/admin flow

Custom persistent Navigator

🔴 Remove

Frappe navigation + Workspace

6. Custom Page 1 — Ledgix POS

This remains the most important custom screen in the system.

Standard Frappe Forms are not optimized for a cashier workflow.

6.1 Target layout

┌──────────────────────────────────────────────────────────────────────┐
│ Ledgix POS       Shift OPEN        Register 01       Ali     10:42 │
├────────────────────────────────────────────┬─────────────────────────┤
│ Scan barcode / Search item...              │ Customer                │
│                                            │ Walk-in Customer      > │
│ All  Grocery  Drinks  Electronics ...      ├─────────────────────────┤
│                                            │ Pepsi        2 × 180    │
│ [Pepsi] [Bread] [Milk] [Water]             │ Bread        1 × 150    │
│                                            │                         │
│ [Coke] [Tissue] [Juice]                    │ Subtotal          510   │
│                                            │ Tax                92   │
│                                            │ TOTAL             602   │
│                                            │                         │
│                                            │      MAKE PAYMENT       │
└────────────────────────────────────────────┴─────────────────────────┘

No permanent second sidebar.

No nested dashboard shell.

No decorative card grid around the actual selling workflow.

6.2 Retail flow

Retail should optimize for speed:

Open Shift
   ↓
Scan/Search Item
   ↓
Cart
   ↓
Optional Customer
   ↓
Discount if permitted
   ↓
Payment
   ↓
Finalize Sale
   ↓
Stock + Tax + FBR
   ↓
80mm Receipt

Retail defaults:

Walk-in Customer

Retail Price List

immediate payment

cashier shift required

fast barcode-first interaction

thermal receipt

minimal required typing

6.3 B2B flow

B2B uses the same cart engine but adds business context:

Select Business Customer
        ↓
Resolve Customer Price List
        ↓
Check Credit / Payment Terms
        ↓
Cart + Tax
        ↓
Payment / Partial Payment / Credit
        ↓
Finalize Sale
        ↓
A4 Tax Invoice

B2B may include:

Business customer required

NTN / STRN / applicable buyer tax identity

default customer Price List

customer-specific payment terms

credit limit

outstanding balance

available credit

A4 invoice

B2B reporting

buyer details included in FBR flow where required

6.4 Sale channel

Do not create a global Retail/B2B system mode.

Every transaction stores its selling context.

Recommended concept:

sale_channel = Retail / B2B

This keeps:

reporting

taxation

receipt behavior

payment rules

customer rules

explicit per transaction.

7. POS Transaction Rules

The UI redesign should preserve the following backend invariants.

7.1 One pricing authority

The browser should never decide the official price.

Price resolution happens server-side using:

explicit allowed override, if authorized

customer/default Price List

item price

effective-date rules

applicable UOM/pack rules if supported

The final Sale Item stores the resolved price as a snapshot.

7.2 One tax authority

Tax calculation happens through the backend Tax Service.

The finalized sale stores an immutable tax snapshot.

Future Tax Profile edits must not rewrite old invoices.

7.3 One stock posting authority

Sale, Purchase, Return and Stock Adjustment should all pass through the same stock service.

Avoid independent code paths directly mutating stock quantities.

This is especially important for:

normal inventory

lots/batches

serial inventory

returns

cancellations

7.4 No silent editing of finalized sales

Once financially finalized:

quantity

item

price

tax

customer billing identity

payment allocations

should not be casually editable.

Use explicit corrective flows.

8. Payments Architecture

Payments deserve a first-class model because they affect both Retail and B2B.

8.1 Recommended structure

Create/standardize:

Ledgix Payment

Core information:

payment date/time

customer

payment method

amount

currency if applicable

reference number

cashier/user

shift/register where relevant

status

reversal reference where applicable

Payment Allocation

A child/allocation structure links payment amounts to:

Sale

Invoice

other supported receivable reference

Example:

Payment P-00015 = 100,000

Allocations:
INV-0101       60,000
INV-0102       40,000

For normal retail, one payment will usually allocate directly to the current Sale.

8.2 Split payment support

POS should be designed so split tender is possible without another data-model rewrite.

Example:

Total      10,000

Cash        4,000
Card        6,000

Even if the first V2 release exposes only the payment methods currently needed, the backend should not assume one Sale = one tender forever.

8.3 Cash change

Retail cash payment should distinguish:

amount due

amount tendered

change returned

Change is not revenue or receivable.

8.4 Payment reversals

Posted payment history should not be silently edited.

Use an explicit reversal/cancellation record with:

original payment

reversing user

timestamp

reason

9. B2B Receivables & Credit

B2B credit is the main backend addition required to make Ledgix a serious retail + B2B product without installing ERPNext.

9.1 Authoritative events

Customer receivable position should be based on:

SALE / INVOICE      increases receivable
PAYMENT             decreases receivable
RETURN / CREDIT     decreases receivable
REVERSAL            reverses the relevant event

9.2 Customer credit view

Customer should expose:

Credit Limit

Outstanding

Available Credit

Overdue

Oldest Due Date

Payment Terms

Default Price List

But Outstanding should be derived from authoritative transactions/allocations.

9.3 Aging

At minimum:

Current

1–30 days

31–60

61–90

90+

The exact presentation can be refined later.

9.4 Scope boundary

Ledgix V2 is not becoming a full ERP.

For now, B2B scope is:

invoice sale

credit sale

payment allocation

customer statement

aging

credit control

returns/credits

tax/FBR

Not mandatory in V2:

quotation

sales order

delivery note

full general ledger

bank reconciliation

chart of accounts

financial statements

Those are ERPNext territory if a future client genuinely needs them.

10. Price Lists

Do not add multiple price columns directly onto Item such as:

retail_price
wholesale_price
distributor_price
special_price

Use proper price-list records.

Recommended model:

Ledgix Price List

Examples:

Retail

Wholesale

Distributor

Potential fields:

name

enabled

selling/buying context if needed

currency if Ledgix later supports multiple currencies

priority/default rules

Ledgix Item Price

Links:

Item + Price List → Rate

Recommended support:

effective from

effective to

enabled

optional UOM/pack context if the current stock model supports it

10.1 Customer price resolution

Customer may have:

default_price_list

POS resolution example:

Business Customer
       ↓
Customer Default Price List = Wholesale
       ↓
Item Price for Wholesale
       ↓
Final Rate Snapshot on Sale Item

11. Shift & Register Control

Shift management is not only a navigation item. It is a financial control.

A usable POS V2 should support:

shift open

opening cash

cashier

register/device identifier if needed

shift start

payment/tender totals

refunds/returns during shift

expected cash

counted cash

variance

shift close

close reason/notes

authorized reopen/correction rules

The exact model should reuse current Ledgix shift functionality where possible instead of creating a second shift system.

11.1 Permission-sensitive POS actions

The following should be permission-controlled:

price override

discount beyond allowed threshold

sale cancellation

return without original invoice

negative stock if ever allowed

backdated transaction

reopen shift

payment reversal

FBR manual retry/override

These rules belong in backend permissions/business logic, not only disabled buttons.

12. Returns

Returns must preserve historical sale truth.

Preferred flow:

Find Original Sale
      ↓
Select Returnable Lines
      ↓
Validate Qty / Serial / Lot
      ↓
Use Original Price + Tax Snapshot
      ↓
Create Sales Return / Credit
      ↓
Restock where applicable
      ↓
Refund / Customer Credit
      ↓
FBR return flow

Do not recalculate an old return using today's:

item price

tax category

notified retail price

customer settings

unless a legal requirement explicitly requires another treatment.

13. Custom Page 2 — Tax & FBR Center

This page remains justified.

Current functionality is broader than simple setup CRUD.

The redesigned page should have only four primary areas:

Tax & FBR Center

1. Overview
2. Tax Mapping
3. Invoice Audit
4. FBR Operations

13.1 Overview

Show operational state, not giant decorative tiles.

Example:

Tax Engine              Enabled
Pricing                  Inclusive
Items Need Review             12
FBR Mode              Production
FBR Connection          Connected
Pending                       4
Failed                        2

Quick links:

Tax Profile

Tax Categories

Tax Rates

Item Tax Profiles

FBR Settings

Those open native Frappe Forms/Lists.

13.2 Tax Mapping

Keep custom because bulk maintenance is genuinely useful.

Examples:

Category → Tax Profile mapping

Item tax review

HS Code

FBR UOM

Sale Type

SRO

Third Schedule

Needs Review

bulk apply

This is more efficient than editing hundreds of Item forms individually.

13.3 Invoice Audit

Merge tax snapshot auditing into one interface.

Search by:

Sale/Invoice

Return

FBR invoice number

customer

date

status

Inspect immutable:

item tax values

taxable value

tax rate

tax amount

notified retail price where relevant

buyer snapshot

FBR payload snapshot

response/reference data

No separate oversized "snapshot modules" are required.

13.4 FBR Operations

Keep:

health

pending queue

failed queue

offline queue

payload preview

validation

submit

retry

submission logs

error inspection

Configuration belongs in native Frappe:

Ledgix FBR Settings

Examples:

mode

credentials/token

retry policy

integration settings

connection configuration

Setup = Native Frappe
Monitoring/Operations = Custom Page

14. Third Schedule / Notified Retail Price

This should be considered part of FBR completion, not an indefinite future enhancement.

Recommended tax concept:

Tax Basis
- Transaction Value
- Notified / Retail Price

and:

Notified Retail Price / Unit

Flow:

Item Tax Profile
      ↓
Tax Service
      ↓
Sale Item Tax Snapshot
      ↓
Immutable Invoice Snapshot
      ↓
FBR Payload

Historical Sale data must retain the actual basis/value used when the invoice was finalized.

15. FBR Reference Data

Where FBR defines controlled values, avoid permanent free-text configuration where practical.

Examples may include:

HS Code

UOM

Sale Type

SRO/reference values

rate/reference mappings

Recommended architecture:

FBR Reference Service
       ↓
Local Site Cache / Reference DocTypes
       ↓
Tax Mapping UI / validation

Tax Center may show:

Reference data last synced: ...
[Sync Reference Data]

Do not create another standalone page only for reference data.

16. FBR Reliability

Existing FBR backend capability should be retained and hardened, not replaced.

Keep/support:

sandbox/production

validation

submission

payload snapshots

submission logs

retry queue

offline queue

locking/idempotency

sale integration

return integration

scheduler processing

Important rule:

A retry must not accidentally create duplicate legal submissions.

Idempotency and submission-state tests are mandatory.

17. Receipts & Invoices

Two major outputs:

Retail

80mm receipt

fast print

business identity

tax/FBR details

QR where required

payment summary

B2B

A4 invoice/PDF

business identity

customer business/tax identity

payment terms

totals/tax

FBR details

outstanding information where appropriate

No hardcoded:

Ledgix Retail Store

or test identity should survive in production print formats.

All identity comes from the current Site's settings.

17.1 Reprint behavior

Recommended:

print/reprint permission

reprint timestamp or indicator where useful

never regenerate historical tax truth from current settings

18. Custom Page 3 — Inventory Intelligence

This custom page remains useful because it answers questions that normal Lists cannot answer efficiently.

Examples:

Where did this serial come from?

Which purchase introduced this lot?

Who bought it?

Was it returned?

What was the margin?

Which stock is slow-moving?

Which stock has risk/anomaly conditions?

Recommended structure:

Inventory Intelligence

1. Overview
2. Item Analysis
3. Lot / Batch Analysis
4. Serial Analysis
5. Risk / Slow Stock

No duplicate app navigation inside it.

No decorative module rainbow.

18.1 Role exposure

Inventory Intelligence does not need to be prominent for every tenant or every role.

Recommended:

Manager: access

Admin: access

Cashier: normally no access

small-store deployments: shortcut may be hidden if unnecessary

The Page can still exist without cluttering every Workspace.

19. Current Dashboard — Delete

Do not maintain a separate custom Dashboard page.

Use the Ledgix Workspace as Manager Overview.

Possible contents:

Number Cards

Charts

Shortcuts

reports

alerts/operational links

recent/important records where native Workspace capabilities support them cleanly

Avoid:

Workspace
   ↓
Custom Dashboard
   ↓
Another card dashboard

20. New Ledgix Workspace

The Workspace becomes the back-office home.

Approximate final structure:

LEDGIX
────────────────────────────────

TODAY
Sales
Gross Profit / Margin
Transactions
Low Stock
FBR Issues

SELLING
Open POS
Sales
Sales Returns
Customers
POS Shifts
Payments

BUYING
Purchases
Suppliers

INVENTORY
Items
Categories
Stock Movements
Stock Lots
Serial Numbers
Inventory Intelligence

REPORTS
Daily Sales
Sales Report
Purchase Report
Returns Report
Current Stock
Low Stock
Customer Statement
Payment / Tender Report

TAX & COMPLIANCE
Tax & FBR Center
Tax Profile
Tax Categories
Tax Rates
Item Tax Profiles
FBR Settings
FBR Submission Logs

ADMINISTRATION
Business Settings
Brand Settings
POS / Stock Settings
Payment Methods
Price Lists
Users
Roles
Maintenance

The exact cards/shortcuts should be adjusted to what Frappe Workspace supports cleanly.

Do not force custom cards where a native shortcut/report link is better.

21. Workspace Is Maintained Continuously

The Workspace should not be rebuilt only at the end.

Every implementation phase that changes:

routes

reports

forms

pages

settings

roles

must update Workspace exposure at the same time.

This prevents a technically complete system with broken navigation.

22. Operations Center — Retire Safely

Operations Center should disappear after its useful capabilities are migrated.

Mapping target:

Current Area

Final Destination

Products

Item List/Form

Categories

Category List/Form

Customers

Customer List/Form

Suppliers

Supplier List/Form

Purchases

Purchase List/Form

Sales

Sale List/Form

Returns

Sales Return List/Form

Stock

Stock Lists/Reports/Intelligence

Shifts

Shift List/Form

special operational actions

relevant Form/List action or custom operational Page

Before deletion:

inspect current local/uncommitted Operations changes

inventory every action

identify its final destination

implement missing action

test

update Workspace

remove the old Page

23. Reports Center — Retire Safely

The custom Reports Center should disappear.

The reports themselves remain.

Use native:

Script Reports

Query Reports where appropriate

Number Cards/Charts for summary metrics

Recommended report set:

Sales

Daily Sales

Sales by Date

Sales by Item

Sales by Category

Sales by Customer

Sales by Channel

Discount / Override Audit where useful

Payments

Payment/Tender Summary

Cashier/Shift Payment Report

Outstanding Receivables

Customer Statement

Aging

Inventory

Current Stock

Low Stock

Stock Movement

Lot/Serial trace reports where native report format makes sense

Buying

Purchases

Supplier Purchases

Returns

Sales Returns

Refunds/Credits

Compliance

FBR Submission Status

Failed/Pending FBR transactions

Tax Audit support reports where useful

Any report currently available only through a custom Reports API/Page must be converted before deletion.

24. Quick Item Scan — Retire

Useful barcode behavior remains.

Primary location:

POS
Scan Barcode → Exact Item → Add to Cart

Optional administration workflow:

Items
Scan/Create/Find Item

No permanent standalone navigation page is required.

If browser camera scanning remains:

package/pin the dependency

do not runtime-load an uncontrolled CDN library

keep camera permission handling route-scoped

25. Custom Persistent Navigator — Remove

Remove the second global navigation system.

Eventually remove:

public/js/ledgix_navigator.js
public/js/ledgix_navigator_config.js
public/css/ledgix_navigator.css

and:

LedgixNavigator.mount(...)

integration.

Final model:

Back Office

Frappe Sidebar + Ledgix Workspace

POS

Minimal purpose-built POS header

Tax / Intelligence

Frappe environment + page-local controls where required

No second permanent Ledgix sidebar.

26. Page Width & Layout

Do not solve custom-page width by globally breaking Frappe.

Avoid global rules such as:

.container {
    max-width: none !important;
}

Instead apply route/page-scoped layout rules.

POS

Use nearly the full available work area.

Tax & FBR

Use a wide but readable operational layout.

Inventory Intelligence

Use a wide analysis layout where tables need it.

Native Frappe Forms/Lists should keep expected Frappe behavior.

27. UI Design System

The new visual language should feel like a professional business application.

27.1 Palette

neutral white/slate surfaces

one Ledgix primary accent

green = success

orange/amber = warning

red = failure/destructive

neutral gray/slate = ordinary information

Avoid module-specific rainbow colors.

27.2 Avoid

random gradients

excessive shadows

giant rounded cards

every control as a pill

icon overload

nested cards inside cards

multiple navigation systems

huge empty hero areas in operational screens

decorative dashboard UI where dense information is more useful

27.3 Use

clear hierarchy

strong typography

compact spacing

useful table density

predictable buttons

consistent statuses

meaningful empty states

accessible contrast

keyboard-friendly POS interactions

28. Global CSS Cleanup

Audit globally loaded assets.

Target:

GLOBAL
- very small Ledgix branding/theme layer only

ROUTE-SCOPED
- POS CSS
- Tax Center CSS
- Inventory Intelligence CSS

Audit ledgix_modal_forms.css before deciding what survives.

Do not keep 15 KB of global modal/form CSS if the same experience can use clean native Frappe Forms.

29. Native Frappe Forms Should Be Properly Designed

Using native Frappe does not mean accepting poor field organization.

Item

Suggested sections/tabs:

General

Identification / Barcode

Pricing

Inventory

Tax / FBR

Status / Audit where needed

Useful List columns:

Code

Item

Category

Effective Selling Price or relevant display value

Stock

Status

Customer

Suggested sections:

General

Business / B2B

Credit

Pricing

Tax / FBR

Address

Contacts

Purchase

clean header

supplier

date/reference

child item table

totals

receiving/stock status

applicable actions

Sale

Primarily audit/inspection after POS creates it.

Show clearly:

channel

customer

items

pricing snapshot

tax snapshot

payments

stock status

FBR status

returns/credits

audit trail

Tax/FBR master forms

Use:

logical sections

descriptions

mandatory validation

role permissions

link fields/reference values where possible

30. Roles & User Experience

Recommended functional roles:

Cashier

Home:

POS

Access normally limited to:

POS

own/current shifts as appropriate

customer lookup required for checkout

receipt/reprint according to permission

returns according to policy

No unnecessary back-office Workspace clutter.

Manager

Home:

Ledgix Workspace

Access:

sales

returns

customers

shifts

buying

inventory

reports

Inventory Intelligence

operational Tax/FBR views

approved override actions

Ledgix Admin

Manager capability plus:

business/site configuration

price lists

payment methods

tax masters

FBR settings/credentials

users/roles as permitted

maintenance controls

Technical Administrator / System Manager

Technical/service-provider access only.

Do not create a broad "Super Admin" business role if Frappe's existing Administrator/System Manager responsibilities already cover the technical layer.

31. Permission Architecture

The current centralized permission-sync approach should remain the main place for role exposure.

But permissions must be tested at all relevant layers:

Workspace visibility
Page access
DocType read/write/create/submit/cancel
Report access
Server/API action
Sensitive configuration

Do not rely on hiding a button as security.

32. Auditability

For a POS product, some actions should produce a clear audit record.

Examples:

price override

excessive discount override

sale cancellation

return/refund

payment reversal

shift variance

reopen shift

FBR manual retry/resubmit

sensitive settings change

Use Frappe audit/version capability where suitable, but financial actions should also retain explicit business references/reasons where needed.

33. Business / Site Settings

Each Frappe Site represents one customer/tenant.

Create/clean a clear Site-level configuration surface.

Recommended separation:

Business Settings

legal/business name

display/store name

address

tax registrations

phone/email

logo/branding reference

default customer

default price list

default warehouse/location if applicable

POS Settings

default selling behavior

receipt settings

allowed discount rules

negative stock policy

shift behavior

barcode behavior

default payment method(s)

Inventory Settings

normal / lot / serial behavior already supported by Ledgix

stock rules

defaults

FBR Settings

Sensitive integration configuration remains separate.

Payment Methods

Maintain separately so methods can be enabled/disabled without changing code.

No tenant secrets belong in Git.

34. ERPNext — Final Decision

Do not install ERPNext for Ledgix V2.

Current Ledgix already owns its main business objects and inventory logic.

Installing ERPNext would introduce overlapping concepts such as:

Item

Customer

Supplier

Sales Invoice

Purchase Invoice

Stock Ledger

Serial/Batch

Price List

Payment Entry

Then we would need to choose which model is authoritative.

That is not simplification. It is a migration/integration project.

Ledgix V2 remains:

Frappe + Ledgix

ERPNext becomes an optional future enterprise/accounting integration if a real customer requires:

General Ledger

P&L

Balance Sheet

Accounts Payable

full Accounts Receivable

Bank Reconciliation

accounting periods

full Order → Delivery → Invoice workflow

35. Multi-Site SaaS Model

Frappe's site model fits Ledgix SaaS well.

Example:

Production Bench
│
├── shop1.ledgix.pk
├── shop2.ledgix.pk
├── abcstore.ledgix.pk
└── demo.ledgix.pk

Shared:

Frappe code

Ledgix app code

static assets

Separated per Site:

database

users

items

customers

sales

purchases

stock

tax setup

FBR credentials

branding

price lists

payment methods

35.1 Versioning rule

One Bench shares one application version.

Therefore production should eventually use:

DEVELOPMENT
    ↓
STAGING BENCH
    ↓ tests/migrations
PRODUCTION BENCH
    ├ Client A
    ├ Client B
    └ Client C

If clients later require incompatible Ledgix versions, use separate production cohorts/benches.

Do not create per-customer Git forks as the normal deployment model.

36. Environment Cleanup

Clarify the difference between configuration examples and the Python virtual environment.

Target:

config/env/
    local.example.env
    production.example.env

Actual Bench Python environment:

frappe-bench/env/

If a root shortcut is useful, an ignored symlink may point to the Bench environment.

Maintain one real Python environment per Bench.

37. Repository Cleanup

After replacements are stable, clean:

old ERP-Prod branding

old README terminology

deprecated navigator assets

deleted Page packages

dead CSS

dead APIs

unused routes

obsolete fixtures

deprecated compatibility code

unused FBR fields

old print-format test identity

stale imports

obsolete install/config references

Keep internal Frappe app name ledgix_saas for now unless a real technical reason justifies renaming it.

Renaming the installed Frappe/Python app provides little customer value and creates avoidable migration risk.

38. Implementation Strategy

The previous plan had the correct destinations, but the implementation order should better protect us from rebuilding the UI twice.

The revised order is below.

Phase 0 — Freeze, Inventory & Baseline

Before destructive changes:

inspect all uncommitted local changes, especially Operations

backup Site database

capture current screenshots

inventory custom Pages

inventory routes

inventory Workspace

inventory permissions

inventory DocTypes

inventory reports

inventory globally injected JS/CSS

capture current FBR payload examples

capture current sale/return/stock behavior

run existing backend test baseline

Create a legacy capability matrix:

Legacy Capability

Current Location

Final Destination

Tested

Safe to Delete

Do not trust placeholder tests as protection.

Add meaningful regression tests for critical financial behavior before demolition.

Phase 1 — Navigation, Roles & Visual Shell

Goal: remove the most obvious UI clutter without deleting business functionality.

Actions:

stop mounting the custom persistent navigator

remove navigator from global Desk experience

simplify globally loaded assets

change homepage routing

Cashier → POS

Manager/Admin → Ledgix Workspace

define role exposure centrally

create/refresh the Ledgix Workspace shell

establish V2 spacing/typography/status design tokens

keep old pages available temporarily through direct routes if still needed during migration

Do not delete Operations/Reports yet.

This gives an immediate visual improvement while preserving fallback access.

Phase 2 — Core Backend Contracts & Additive Migrations

Before the final POS rewrite, lock the data model it will depend on.

Implement/standardize as required:

sale_channel

authoritative pricing resolution

Price List / Item Price model

Payment model

Payment allocations

B2B customer pricing/credit fields

return linkage to original sale lines

immutable sale price/tax snapshots

Third Schedule / notified retail price model

shift/register financial rules

standardized stock-posting service boundary

Site-level Business/POS settings cleanup

Migrations should be:

additive where possible

idempotent

tested on existing data

safe to rerun

backward-compatible until V2 cutover

This phase prevents the new POS from being built around temporary fields.

Phase 3 — Workspace V2 + Native Back-Office Foundations

Build the real Ledgix Workspace.

Clean key native Forms/Lists:

Item

Category

Customer

Supplier

Purchase

Sale

Return

Shift

Payment

Price List

Tax/FBR masters

Add:

useful list columns

filters

status indicators

contextual Form actions

role-aware shortcuts

Continue leaving legacy Operations/Reports routes available until parity is proven.

Phase 4 — POS V2 Core

Rebuild the POS around the new backend contracts.

Priority order:

shift requirement

exact barcode lookup

fast item search

cart

pricing service integration

tax service integration

customer selection

discount/override permissions

payment flow

finalize transaction

stock posting

FBR handoff

receipt

hold/resume if retained

keyboard/scanner ergonomics

responsive behavior for intended register screens

First stabilize Retail.

Do not overload the first pass with every B2B screen before the core transaction is reliable.

Phase 5 — Operations Migration & Retirement

For every Operations Center feature:

Current feature
    ↓
Native Form/List/Workspace/Custom Page destination
    ↓
Implement
    ↓
Permission test
    ↓
Functional test

Then delete Operations Center.

Update Workspace in the same change.

Phase 6 — Reports Migration & Retirement

Validate every existing report/API.

Convert required reports to:

Script Reports

Query Reports

Workspace Number Cards/Charts where appropriate

Add the new payment/B2B reports required by the new backend.

When parity is confirmed:

delete Reports Center

delete obsolete reports API code

update Workspace

Phase 7 — Tax & FBR Center V2

Redesign the retained Tax & FBR Center.

Implement:

Overview

Tax Mapping

Invoice Audit

FBR Operations

Third Schedule/notified retail price support

controlled reference-data improvements

buyer/business context required for B2B flow

receipt/invoice compliance cleanup

QR handling where required

stronger idempotency/retry tests

submission audit improvements

Keep simple setup in native Forms.

Phase 8 — B2B Completion

Now expose the B2B selling experience on top of the already-prepared backend.

Implement:

B2B customer mode

customer Price List

business/tax identity

payment terms

credit limit

outstanding

available credit

partial payment

credit sale

payment allocation

customer statement

aging

B2B invoice

B2B/retail report split

FBR buyer flow

Do not create a separate B2B app or duplicate cart engine.

Phase 9 — Inventory Intelligence V2

Retain the valuable analysis logic.

Redesign UI into:

Overview

Item Analysis

Lot/Batch Analysis

Serial Analysis

Risk/Slow Stock

Only refactor the backend module into smaller services if it improves testability or maintainability.

Do not refactor large working modules purely for aesthetics.

Phase 10 — Quick Scan Retirement

Ensure scanning is complete in POS.

If an administration scan workflow is genuinely useful, place it under Item administration.

Then remove:

standalone Quick Item Scan Page

route

assets

obsolete scanner dependency wiring

Phase 11 — Deep Cleanup & Dead-Code Removal

Once all migration gates are green:

Delete obsolete:

Pages

JS

CSS

routes

APIs

fixtures

imports

package entries

compatibility code

old settings

legacy navigation

duplicate reports logic

Run migration/update patches.

Re-run the capability matrix to ensure no lost functionality.

Phase 12 — QA, Deployment & SaaS Hardening

Before calling V2 production-ready:

Functional

retail checkout

barcode

discount

payment

split payment if exposed

return/refund

shift close

purchase

stock

lot/serial

B2B credit

customer statement

reports

FBR

Permission

Test each important action as:

Cashier

Manager

Admin

unauthorized normal user

Financial/Data Integrity

Test:

duplicate submit protection

duplicate FBR retry protection

stock consistency

return quantity limits

original tax snapshot preservation

payment reversal

credit/outstanding correctness

shift variance

migration idempotency

Deployment

Prepare:

staging Bench

production Bench

multi-site provisioning

backup/restore procedure

wildcard/subdomain plan

TLS

worker health

scheduler health

FBR health

log rotation/inspection

per-site health check

automated backups

migration procedure

rollback procedure

version upgrade checklist

39. Definition of Done for Removing a Legacy Page

A custom legacy Page can be removed only if all are true:

Every useful feature has a mapped destination

Replacement is implemented

Replacement permissions are correct

Workspace links are updated

Direct links/routes are updated

Automated tests cover critical behavior

Manual smoke test passes

No backend action exists only through the old Page

No report exists only through the old Page

No global asset depends on the old Page

Delete/migration patch is safe

Site migration succeeds

No console/server errors after removal

40. Critical Test Gates

The following should become non-negotiable regression coverage.

Sales

finalized total is deterministic

price snapshot does not change later

tax snapshot does not change later

duplicate finalize does not create duplicate transaction

Stock

Sale reduces stock once

Return restores correct stock once

Purchase increases stock once

cancellation/reversal behavior is deterministic

lot/serial ownership/history stays valid

Payments

payment allocations sum correctly

split payments sum correctly

reversal restores receivable correctly

retail change is not treated as payment value

B2B

credit limit enforcement

outstanding calculation

available credit

return reduces receivable correctly

payment can allocate to correct invoices

statement totals reconcile

FBR

payload values match immutable Sale snapshot

retry is idempotent

successful submission is not duplicated

failed/pending/offline transitions are valid

return references remain valid

Permissions

Cashier cannot perform Manager/Admin actions through API

Manager cannot read/change secrets that are Admin-only

workspace visibility matches permissions

direct URL does not bypass authorization

41. Final Product Footprint

CUSTOM PAGES
│
├── Ledgix POS
├── Tax & FBR Center
└── Inventory Intelligence


FRAPPE WORKSPACE
│
├── Manager Overview
├── KPIs
├── shortcuts
├── reports
└── operational links


NATIVE FRAPPE
│
├── Items
├── Categories
├── Customers
├── Suppliers
├── Sales
├── Sales Returns
├── Purchases
├── Payments
├── Shifts
├── Price Lists
├── Item Prices
├── Stock
├── Lots
├── Serials
├── Tax Masters
├── FBR Settings/Logs
├── Reports
├── Users
├── Roles
└── Administration

42. Locked Product Decisions

Unless implementation evidence gives a strong reason to reopen them, treat these as locked.

Frappe + Ledgix, no ERPNext dependency for V2.

Only three major custom Pages.

No permanent second Ledgix sidebar.

Workspace is the Manager back-office home.

Standard CRUD uses native Frappe.

POS remains custom.

Tax/FBR operations remain custom; setup remains native.

Inventory Intelligence remains custom.

Retail and B2B share one Sale/Stock/Tax backend.

Retail/B2B is stored per Sale, not a global system mode.

Proper Price Lists replace multiple price columns on Item.

B2B uses authoritative payment/receivable events.

Finalized financial/tax snapshots are immutable.

Stock posting has one authoritative service path.

Historical returns use original transaction truth.

FBR remains core and is not rebuilt from zero.

Third Schedule/notified retail price is part of FBR completion.

Each customer is a separate Frappe Site.

App code is shared at Bench level.

No tenant secrets or customer-specific configuration in Git.

Legacy UI is removed only after tested parity.

ledgix_saas internal app name stays for now.

43. Explicit Non-Goals for V2

To prevent the project from becoming unnecessarily heavy, V2 does not need to become:

full accounting ERP

HR/payroll system

CRM platform

e-commerce platform

restaurant management system

warehouse management suite beyond Ledgix's required stock capabilities

AI analytics platform

full offline-first POS

multi-company accounting platform

These can be separate future products/modules if actual customers require them.

44. Implementation-Time Decisions We Can Still Adjust

The plan is intentionally strict on architecture but flexible on implementation details.

We may still change:

exact POS component layout

exact Workspace card arrangement

field naming after inspecting current schema

whether some settings merge into one Single DocType

exact report list

exact Inventory Intelligence tab names

exact payment UI

whether a small native action is better than a custom modal

internal service/module file layout

performance optimizations

CSS implementation details

But changes should preserve the core rules:

Native where native is enough.
Custom where workflow justifies it.
One backend truth.
No duplicated business logic.
No destructive deletion before parity.
No visual redesign at the cost of data integrity.

45. Final Target Experience

Cashier

Login
  ↓
POS
  ↓
Scan
  ↓
Pay
  ↓
Receipt

Fast and uncluttered.

Manager

Login
  ↓
Ledgix Workspace
  ├ Sales
  ├ Inventory
  ├ Buying
  ├ Reports
  ├ Intelligence
  └ Compliance

No duplicate navigation.

Admin

Workspace
  ↓
Operational Management
  +
Configuration
  +
Users/Roles
  +
Tax/FBR

46. Final Architecture Statement

Ledgix V2 should feel like one coherent POS product built on Frappe, not a custom frontend sitting beside Frappe.

The design principle is:

Use Frappe as the back-office framework. Use custom UI only for workflows where Frappe's standard UI is genuinely the wrong tool. Keep all financial, stock, pricing, payment, tax and FBR truth in shared backend services.

That gives us:

cleaner UX

less code

less duplicated logic

easier maintenance

safer migrations

stronger permissions

easier SaaS deployment

proper Retail + B2B support

room for future enterprise integration without contaminating the lightweight product

This is the architecture to use as the master plan.md while implementation proceeds phase by phase.