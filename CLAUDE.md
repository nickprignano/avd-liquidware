@AGENTS.md

# CLAUDE.md

avd-liquidware: the optional Liquidware tier for Azure Virtual Desktop, deployed against an existing [avd-landing-zone](https://github.com/nickprignano/avd-landing-zone) landing zone. `stratusphere/` is the Stratusphere UX assessment instrument (its own CLAUDE.md); `scripts/Deploy-LiquidwareTier.ps1` is the one entry point for the tier (ProfileUnity, FlexApp, Stratusphere). Design: `docs/deploy-spec.md` and its red-team review, `docs/deploy-redteam.md`.

## Validate before pushing
CI (`.github/workflows/tier.yml`; `stratusphere.yml` for `stratusphere/`) runs:

```bash
pwsh -c "Invoke-ScriptAnalyzer -Path scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 -EnableExit"
pwsh -c "Invoke-Pester -Path ./tests -CI"
```

## Rules
- **The landing zone's default deployment never changes.** The tier reads the landing zone by its naming convention and writes only the child resources listed in `docs/deploy-spec.md` §4, each removed by `Cleanup`.
- **Checks are pure functions** in `scripts/LiquidwareTier.psm1` (prefix `Lw`), taking data read from Azure, tested offline with fixtures that omit empty properties the way ARM does. Approved verbs: `Get-` for functions that only build data.
- **No cloud run without a written cost estimate and Nick's go.** Sandbox: Nick's personal subscription, northcentralus, smallest sizes, `Cleanup` right after, teardown evidence. Offline checks first (Pester, what-if).
- **No Liquidware binaries, license material or customer data in this repo.** Operator output goes to `output/` (git-ignored).
- **Never make operators remember secrets; secrets never go through chat.** VMs read secrets with their own managed identities; the operator writes them through the management plane; anything a Run Command must carry goes in protected parameters.
- **Liquidware is the only partner.** No Nerdio dependency; other vendors only as prior art.
- **Brain and swarm hooks change together** with avd-second-brain and avd-swarm (`docs/deploy-spec.md` §14).
- **Personal project, not for production, as is, not affiliated with the author's employer, Liquidware or Microsoft.** The notice at the top of every entry point stays (a test checks it).
- **American English** in docs, script output and comments. Scripts stay ASCII (CI's analyzer flags non-ASCII files without a BOM): write "section 4", not the section sign.
