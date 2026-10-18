# CLAUDE.md (stratusphere/)

Everything here lives under `stratusphere/` in avd-liquidware; run the commands below from this folder. Stratusphere UX deployment for AVD readiness assessments: Bicep at subscription scope (`bicep/`) deploys the appliances (Hub, optional Database and Collectors) from Azure Marketplace, `scripts/ops/Deploy-Stratusphere.ps1` plans, checks, deploys, fixes and cleans them up by role (`scripts/deploy/deploy.sh` is the bash deploy-only path), and PowerShell scripts for Azure Cloud Shell (`scripts/ops/`) check readiness (`Test-StratusphereReadiness.ps1`: quota, policy, network, the endpoints' callback path, and a current-state capture), roll out the Connector ID Key (`Deploy-CidKey.ps1`) and, later, export assessment data. Conventions follow [avd-landing-zone](https://github.com/nickprignano/avd-landing-zone).

## Validate before pushing
CI (`.github/workflows/stratusphere.yml`, at the repo root) runs all of these:

```bash
bicep lint bicep/main.bicep
SSUX_ADMIN_PASSWORD='Placeholder-only-1!' SSUX_KV_READER_ID=00000000-0000-0000-0000-000000000001 \
  bicep build-params parameters/lab.bicepparam --stdout > /dev/null
pwsh -c "Invoke-ScriptAnalyzer -Path scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 -EnableExit"
pwsh -c "Invoke-Pester -Path ./tests -CI"
shellcheck scripts/deploy/deploy.sh
```

## Rules
- **Real runs are the source of truth.** Much of the appliance's behavior in Azure (first boot, which credential it honors, API coverage) is unverified. When a real run shows something, fix it, add a guard (Pester test or preflight check), and note it in `docs/lessons/`.
- **No Liquidware binaries or license material in the repo.** The Hub comes from Marketplace; the Connector ID Key installer is fetched from the user's own Hub.
- **Marketplace images need a matching `plan` block** (`tests/Template.Tests.ps1` guards it). Terms are accepted by `Deploy-Stratusphere.ps1`, `deploy.sh` or the preflight's `-Fix`, per subscription and plan.
- **Preflight checks are pure functions** in `scripts/ops/StratusphereReadiness.psm1` that take data read from Azure and return results, so they are tested offline. Approved verbs: `Get-` for functions that only build data.
- **Assessment exports hold user and machine names.** They go to `output/` (git-ignored), never into the repo or issues.
- **Never make operators remember secrets.** Generated credentials go to Key Vault, and reruns reuse them (an appliance keeps the password it was created with).
- **Optional env vars in `.bicepparam`:** `empty(readEnvironmentVariable('X', ''))` guards, because set-but-empty must fall back to the default.
- **Personal project, not for production, as is, not affiliated with the author's employer, Liquidware or Microsoft.** No license is chosen yet (Nick decides), so none is claimed. The README warning and the one-line notice at the top of every entry point stay (a test checks entry points).
- **American English** in docs, script output and comments.
