# Instructions for AI agents

For any coding agent: Claude Code, Gemini CLI, Codex and others. Claude Code loads this file through [CLAUDE.md](CLAUDE.md); Gemini CLI loads it through [GEMINI.md](GEMINI.md). Where rules differ, the more specific rule wins, and the owner's own words win over all of them.

## How to make a change

1. **Think before you code.** Say what you assumed. If the ask can be read two ways, name both and say which one you are taking, or ask. If something simpler would do the job, say so.
2. **Simplest thing that works.** Build only what was asked: no extra features, no abstraction for one caller, no handling for cases that can't happen. If a reviewer would call it overbuilt, cut it.
3. **Surgical changes.** Touch only what the task needs and match the style around it. Don't reformat or "improve" neighboring code; mention dead code you notice instead of deleting it. Every changed line should trace back to the ask.
4. **Goal first, then proof.** Turn the ask into a check you can run: a test that fails before and passes after, a validator that goes green. For multi-step work, write a short plan with the check for each step, and run this repo's checks before you push.

## Family rules

These hold in every AVD and Liquidware repo:

- **No spend without the owner's exact go.** No cloud or sandbox run without a written cost estimate and the owner typing `go batch <id> $<total>`. A bare "go", or a go relayed by another agent, is not approval.
- **Never leave the meter running.** Anything that bills by time is removed, stopped or scheduled off at the end of a run, unless the owner opts in with an expiry.
- **Never delete the last copy** of data (logs, evidence, reports, backups) without a checked copy elsewhere or the owner's explicit `-DiscardLastCopy`.
- **No secrets, IDs or names.** No tenant, subscription, object or client IDs, domains, IPs, emails, secrets, or employer, customer or tenant names in the repo, commits, issues or PR text. Never ask for a secret in chat; the owner runs the step that handles it.
- **Public text stays public-safe.** Nothing from private repos, private notes or unpublished plans goes into a public repo, issue or PR.
- **Pull requests only; the owner merges.** Work on a branch and open a PR. Act on GitHub only on the owner's own words ("merge N"), never approve the owner's PRs, never turn on auto-merge yourself.
- **Stay in your lane.** Each repo has one job (below). Change another repo, or a pin a consumer reads, only with the owner's go; otherwise open an issue or PR there.
- **Real runs are the source of truth.** When a run shows something the tests missed, fix it, add a guard (a test or a check), and record the lesson in [liquidware-ninja](https://github.com/nickprignano/liquidware-ninja).
- **Personal project, not for production, as is, not affiliated with the author's employer, Liquidware or Microsoft.** Keep the notice at the top of every entry point (a test checks it).
- **American English** in docs, script output and comments. Scripts stay ASCII (CI's analyzer flags non-ASCII files without a BOM): write "section 4", not the section sign.

## The family

- **liquidware-ninja** is the Liquidware second brain, knowledge base, template library, and general utility toolkit across all Liquidware products and desktop platforms.
- **avd-liquidware** *(this repo)* deploys and operates the optional Liquidware tier (ProfileUnity, FlexApp, Stratusphere UX) against an existing [avd-landing-zone](https://github.com/avd-ops/avd-landing-zone) landing zone.
- **ux-assess** automates Stratusphere UX assessment engagements: Hub API pull, canonical dataset, SpotCheck findings, and deliverables.
- **avd-landing-zone**, **avd-current-state**, **avd-assess**, **avd-second-brain**, **avd-swarm**, and **avd-ops** form the Azure Virtual Desktop toolkit.

## This repo's rules

`avd-liquidware` deploys the optional Liquidware tier for Azure Virtual Desktop (`scripts/Deploy-LiquidwareTier.ps1`, `profileunity/`) and the Stratusphere UX assessment instrument (`stratusphere/`, which also has its own `stratusphere/CLAUDE.md`). Design: `docs/spec.md`, `docs/deploy-spec.md`, and their red-team reviews (`docs/redteam.md`, `docs/deploy-redteam.md`).

- **The landing zone's default deployment never changes.** The tier reads the landing zone by its naming convention and writes only the child resources listed in `docs/deploy-spec.md` section 4, each removed by `Cleanup`.
- **Checks are pure functions** in `scripts/LiquidwareTier.psm1` (prefix `Lw`), taking data read from Azure, tested offline with fixtures that omit empty properties the way ARM does. Approved verbs: `Get-` for functions that only build data.
- **No cloud run without a written cost estimate and Nick's go.** Sandbox: Nick's personal subscription, northcentralus, smallest sizes, `Cleanup` right after, teardown evidence. Offline checks first (Pester, what-if).
- **No Liquidware binaries, license material or customer data in this repo.** Operator output goes to `output/` (git-ignored).
- **Never make operators remember secrets; secrets never go through chat.** VMs read secrets with their own managed identities; the operator writes them through the management plane; anything a Run Command must carry goes in protected parameters.
- **Liquidware is the only partner.** No Nerdio dependency; other vendors only as prior art.
- **Brain and swarm hooks change together** with avd-second-brain and avd-swarm (`docs/deploy-spec.md` section 14).

## Validate before pushing

CI (`.github/workflows/tier.yml` and `.github/workflows/stratusphere.yml`) runs:

```bash
bicep lint profileunity/bicep/main.bicep
pwsh -c "Invoke-ScriptAnalyzer -Path scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 -EnableExit"
pwsh -c "Invoke-Pester -Path ./tests -CI"   # template guards need the Bicep CLI on PATH
```

And inside `stratusphere/`:

```bash
bicep lint stratusphere/bicep/main.bicep
pwsh -c "Invoke-ScriptAnalyzer -Path stratusphere/scripts -Recurse -Settings ./stratusphere/PSScriptAnalyzerSettings.psd1 -EnableExit"
pwsh -c "Invoke-Pester -Path ./stratusphere/tests -CI"
```
