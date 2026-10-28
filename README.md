# avd-liquidware

Part of [avd-ops](https://avd-ops.dev/), the open toolkit for Azure Virtual Desktop.

Automation for running **Liquidware** products in **Azure**: **Stratusphere UX** for assessments, and an optional tier for Azure Virtual Desktop (**ProfileUnity** for profile portability and user environment management, **FlexApp** packages through AVD app attach, **CommandCTRL** for support) deployed against an existing [avd-landing-zone](https://github.com/avd-ops/avd-landing-zone) landing zone. FSLogix stays the profile container.

The shared Liquidware knowledge base, templates, and cross-platform utilities live in **[liquidware-ninja](https://github.com/nickprignano/liquidware-ninja)**, and the Stratusphere UX assessment & deliverable pipeline lives in **[ux-assess](https://github.com/nickprignano/ux-assess)**.

> [!WARNING]
> **Personal project. Research and learning only. Not for production. No warranty.**
>
> - This is my own personal project, built on my own time **for research and learning**. It is **not affiliated with, endorsed by or supported by my employer**, and it does not represent my employer's views, products or guidance.
> - It is **not affiliated with or endorsed by Liquidware** or Microsoft. Stratusphere is Liquidware's product; this repo only automates deploying and using it. **Bring your own Liquidware licenses.** Liquidware, ProfileUnity, FlexApp, Stratusphere and CommandCTRL are trademarks of Liquidware; Azure, Microsoft Entra, Intune and FSLogix are trademarks of Microsoft.
> - **Do not run it in production** or against subscriptions and tenants that matter. Test it first in a dedicated lab subscription.
> - It is provided **"as is", without warranty of any kind**, under the [MIT License](LICENSE). You use it at your own risk: you are responsible for what it deploys, for the Azure charges it incurs, and for reviewing the code before you run it.
> - **Contributions and forks are welcome and encouraged.** See [Contributing](#contributing).

## What's here

| Folder | What it is |
|---|---|
| [stratusphere/](stratusphere/README.md) | Stratusphere UX in Azure: preflight, the Hub, Database and Collector appliances, Connector ID Key rollout, teardown. Bicep and PowerShell for Azure Cloud Shell |
| [profileunity/](profileunity/bicep/main.bicep) | Subscription-scoped Bicep for the ProfileUnity and FlexApp tier (`rg-<base>-liquidware`, spoke peering, DNS links, Key Vault, `lwconfig` / `media` / `appattach` storage, Console VM) |
| [scripts/](scripts/Deploy-LiquidwareTier.ps1) | `Deploy-LiquidwareTier.ps1`, the one entry point for the tier (ProfileUnity, FlexApp, Stratusphere) against a landing zone, plus `LiquidwareTier.psm1`, `Publish-LiquidwareMedia.ps1`, `Set-LiquidwareSecret.ps1`, and host Run Commands |
| [docs/spec.md](docs/spec.md) | The tier: which product owns what, identity and storage per path, security, cost, phases ([red-team](docs/redteam.md), [decision AL-0001](docs/decisions/AL-0001-optional-tier.md)) |
| [docs/deploy-spec.md](docs/deploy-spec.md) | How the tier is deployed, end to end, by script ([red-team](docs/deploy-redteam.md), [decision AL-0002](docs/decisions/AL-0002-automated-deployment.md)) |
| [docs/console.md](docs/console.md) | The ProfileUnity console's manual steps until its silent install is verified (V18) |

## The Liquidware second brain

All research findings, product architecture, Stratusphere API & SpotCheck references, known errors, and decision records across Liquidware products live in **[liquidware-ninja](https://github.com/nickprignano/liquidware-ninja/tree/main/docs/knowledge)**.

## Guardrails

The repo is public. Nothing in it identifies a real tenant, subscription, employer or customer, secrets never pass through it or through chat, no Liquidware binaries or license material are committed, and every change goes through a reviewed pull request. The full rules are in [docs/guardrails.md](docs/guardrails.md) and [AGENTS.md](AGENTS.md).

## Contributing

Contributions and forks are welcome and encouraged. Before you open a pull request, run the checks in [AGENTS.md](AGENTS.md) and follow the [guardrails](docs/guardrails.md). Keep tenant data, IDs and secrets out of the repo, issues and pull requests. No Liquidware binaries, license material or assessment exports, ever.

## License

MIT ([LICENSE](LICENSE)).
