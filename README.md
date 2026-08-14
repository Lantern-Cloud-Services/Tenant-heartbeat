# Tenant-heartbeat

Weekly GitHub Actions workflows that keep two Azure tenants "warm" by creating or updating a
heartbeat resource group in a subscription in each tenant.

## What it does

| Workflow | Tenant | GitHub environment | Schedule (UTC) |
| --- | --- | --- | --- |
| `.github/workflows/heartbeat-lcs-p3.yml` | LCS P3 | `lcs-p3` | Mondays 03:00 |
| `.github/workflows/heartbeat-lcs-e5.yml` | LCS E5 | `lcs-e5` | Mondays 03:30 |

Both call the reusable workflow `.github/workflows/heartbeat.yml`, which signs in to Azure
with OIDC (no stored secrets) and runs a subscription-scope Bicep deployment
(`infra/heartbeat.bicep`). The deployment is idempotent: it creates the resource group on
first run and refreshes its `lastHeartbeatUtc` tag on every later run.

Each workflow can also be started manually (`workflow_dispatch`), optionally with
`what_if=true` for a read-only preview.

## Setup

See **[docs/admin-setup.md](docs/admin-setup.md)** for the step-by-step administrator guide
(app registration, federated credentials, role assignment, GitHub environment variables).

## Configuration

Per-tenant settings live as GitHub **environment variables** — no code changes needed to
retarget a tenant:

`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `RESOURCE_GROUP_NAME`, `LOCATION`

## Repository layout

```
.github/workflows/heartbeat.yml           reusable deployment workflow
.github/workflows/heartbeat-lcs-p3.yml    weekly schedule for LCS P3
.github/workflows/heartbeat-lcs-e5.yml    weekly schedule for LCS E5
.github/workflows/validate.yml            builds/lints the Bicep template on PRs
infra/heartbeat.bicep                     subscription-scope resource group definition
docs/admin-setup.md                       administrator setup guide
```
