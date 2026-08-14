# Administrator setup guide

This guide wires up the two Azure tenants (**LCS P3** and **LCS E5**) so the weekly
heartbeat workflows can create/update a resource group in each one.

The design uses **workload identity federation (OIDC)** — GitHub Actions receives a
short-lived token from Entra ID at run time. **No client secrets or certificates are ever
stored in GitHub.**

Repeat every step once per tenant. Values that differ per tenant are marked `<...>`.

| Item | LCS P3 | LCS E5 |
| --- | --- | --- |
| GitHub environment name | `lcs-p3` | `lcs-e5` |
| Workflow | `.github/workflows/heartbeat-lcs-p3.yml` | `.github/workflows/heartbeat-lcs-e5.yml` |

---

## 0. Prerequisites

- Azure CLI 2.60+ (`az version`) and GitHub CLI (`gh auth login`) installed locally.
- In each tenant: permission to create an app registration (Application Developer or
  Application Administrator) and to assign roles at subscription scope (Owner or User
  Access Administrator).
- Admin on the `Lantern-Cloud-Services/Tenant-heartbeat` repository.

Set the shared values once:

```powershell
$GH_REPO  = "Lantern-Cloud-Services/Tenant-heartbeat"
$APP_NAME = "github-tenant-heartbeat"
```

> All commands below use **PowerShell** syntax. Keep the same PowerShell window open for
> the whole run so the `$VARIABLES` you set stay in scope.

---

## 1. Create the app registration in the tenant

```powershell
az login --tenant <TENANT_ID> --allow-no-subscriptions
az account set --subscription <SUBSCRIPTION_ID>

$APP_ID = az ad app create --display-name $APP_NAME --query appId -o tsv
az ad sp create --id $APP_ID
Write-Host "AZURE_CLIENT_ID = $APP_ID"
```

> The app registration lives in the tenant. Because each tenant is separate, you create one
> app registration per tenant — they are unrelated to each other.

---

## 2. Add the federated credentials

Federated credentials tell Entra ID exactly which GitHub workflow may sign in. Scope them
to the **environment** so only the heartbeat job for that tenant can use the identity.

```powershell
$ENVIRONMENT = "<lcs-p3|lcs-e5>"

@"
{
  "name": "github-env-$ENVIRONMENT",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:$GH_REPO:environment:$ENVIRONMENT",
  "audiences": ["api://AzureADTokenExchange"]
}
"@ | Set-Content -Path fic.json -Encoding ascii

az ad app federated-credential create --id $APP_ID --parameters '@fic.json'
```

> The JSON is written to `fic.json` first because PowerShell quoting mangles inline JSON.
> `az` reads it back with the `@` prefix. Delete the file afterwards if you like.

That single credential covers both the weekly schedule and manual runs, because the job
always targets the environment.

---

## 3. Grant the least-privilege role on the subscription

The workflow only needs to create/update a resource group and its tags. Assign
**Contributor** scoped to the subscription (simplest supported option), or see the
hardening note below for a tighter custom role.

```powershell
$SP_OBJECT_ID = az ad sp show --id $APP_ID --query id -o tsv

az role assignment create `
  --assignee-object-id $SP_OBJECT_ID `
  --assignee-principal-type ServicePrincipal `
  --role "Contributor" `
  --scope "/subscriptions/<SUBSCRIPTION_ID>"
```

<details>
<summary>Optional hardening: custom "Heartbeat Resource Group Writer" role</summary>

```powershell
@"
{
  "Name": "Heartbeat Resource Group Writer",
  "Description": "Create/update resource groups and read deployments for tenant heartbeat.",
  "Actions": [
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/subscriptions/resourceGroups/write",
    "Microsoft.Resources/deployments/*",
    "Microsoft.Resources/subscriptions/read",
    "Microsoft.Resources/subscriptions/locations/read"
  ],
  "NotActions": [],
  "AssignableScopes": ["/subscriptions/<SUBSCRIPTION_ID>"]
}
"@ | Set-Content -Path heartbeat-role.json -Encoding ascii

az role definition create --role-definition heartbeat-role.json
az role assignment create `
  --assignee-object-id $SP_OBJECT_ID `
  --assignee-principal-type ServicePrincipal `
  --role "Heartbeat Resource Group Writer" `
  --scope "/subscriptions/<SUBSCRIPTION_ID>"
```

Note the role grants no delete permission, so the heartbeat can never remove resources.
</details>

---

## 4. Create the GitHub environment and variables

All values below are non-secret identifiers, so they are stored as **environment
variables** (not secrets) — this keeps logs readable and avoids secret sprawl.

```powershell
$ENVIRONMENT = "<lcs-p3|lcs-e5>"

gh api -X PUT "repos/$GH_REPO/environments/$ENVIRONMENT" | Out-Null

gh variable set AZURE_CLIENT_ID       --repo $GH_REPO --env $ENVIRONMENT --body $APP_ID
gh variable set AZURE_TENANT_ID       --repo $GH_REPO --env $ENVIRONMENT --body "<TENANT_ID>"
gh variable set AZURE_SUBSCRIPTION_ID --repo $GH_REPO --env $ENVIRONMENT --body "<SUBSCRIPTION_ID>"
gh variable set RESOURCE_GROUP_NAME   --repo $GH_REPO --env $ENVIRONMENT --body "rg-tenant-heartbeat"
gh variable set LOCATION              --repo $GH_REPO --env $ENVIRONMENT --body "eastus"
```

Required variables per environment:

| Variable | Example | Notes |
| --- | --- | --- |
| `AZURE_CLIENT_ID` | `00000000-...` | App registration (client) ID from step 1 |
| `AZURE_TENANT_ID` | `00000000-...` | Directory (tenant) ID |
| `AZURE_SUBSCRIPTION_ID` | `00000000-...` | Target subscription in that tenant |
| `RESOURCE_GROUP_NAME` | `rg-tenant-heartbeat` | Resource group created/updated weekly |
| `LOCATION` | `eastus` | Azure region |

Optionally restrict each environment's deployment branches to `main` in
**Settings → Environments → \<environment\> → Deployment branches**, so a fork or feature
branch can never assume the identity.

---

## 5. Verify

Run a what-if (read-only) preview first, then a real run:

```powershell
gh workflow run heartbeat-lcs-p3.yml --repo $GH_REPO -f what_if=true
gh workflow run heartbeat-lcs-p3.yml --repo $GH_REPO

gh workflow run heartbeat-lcs-e5.yml --repo $GH_REPO -f what_if=true
gh workflow run heartbeat-lcs-e5.yml --repo $GH_REPO
```

Confirm the resource group exists and shows a fresh `lastHeartbeatUtc` tag:

```powershell
az group show --subscription <SUBSCRIPTION_ID> --name rg-tenant-heartbeat --query tags
```

After verification the workflows run automatically every Monday (03:00 UTC for LCS P3,
03:30 UTC for LCS E5).

---

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `AADSTS70021: No matching federated identity record found` | The `subject` in step 2 must exactly match `repo:<owner>/<repo>:environment:<environment>` (case-sensitive). |
| `Environment variable 'X' is not configured` | A variable from step 4 is missing on that environment. |
| `AuthorizationFailed` on deployment | Role assignment from step 3 missing, or scoped to the wrong subscription. |
| Scheduled runs stop firing | GitHub disables schedules in repos with no activity for 60 days — push a commit or re-enable the workflow. |

## Security notes

- No secrets are stored in GitHub; access relies on short-lived OIDC tokens.
- Each tenant has its own identity, environment, and role assignment — no shared blast radius.
- `permissions` in every workflow is limited to `contents: read` and `id-token: write`.
- Federated credentials are bound to a specific repository *and* environment.
- Rotate/revoke access by deleting the app registration or the federated credential; nothing
  needs to change in GitHub except the environment variables.
