# avd-liquidware

Automation for running **Liquidware** products in **Azure**: Stratusphere UX for assessments, and an
optional tier for Azure Virtual Desktop (**ProfileUnity** for profile portability and user environment
management, **FlexApp** packages through AVD app attach, **CommandCTRL** for support) deployed against
an existing [avd-landing-zone](https://github.com/nickprignano/avd-landing-zone) landing zone. FSLogix
stays the profile container. It also keeps a living knowledge base of what we learn along the way.

> [!WARNING]
> **Personal project. Research and learning only. Not for production. No warranty.**
>
> - This is my own personal project, built on my own time **for research and learning**. It is **not affiliated with, endorsed by or supported by my employer**, and it does not represent my employer's views, products or guidance.
> - It is **not affiliated with or endorsed by Liquidware** or Microsoft. Stratusphere is Liquidware's product; this repo only automates deploying and using it. **Bring your own Liquidware licenses.** Liquidware, ProfileUnity, FlexApp, Stratusphere and CommandCTRL are trademarks of Liquidware; Azure, Microsoft Entra, Intune and FSLogix are trademarks of Microsoft.
> - **Do not run it in production** or against subscriptions and tenants that matter. Test it first in a dedicated lab subscription.
> - It is provided **"as is", without warranty of any kind**, under the [MIT License](LICENSE), with the knowledge base tooling under Apache-2.0 (see [License](#license)). You use it at your own risk: you are responsible for what it deploys, for the Azure charges it incurs, and for reviewing the code before you run it.
> - **Contributions and forks are welcome and encouraged.** See [Contributing](#contributing).

## What's here

| Folder | What it is |
|---|---|
| [stratusphere/](stratusphere/README.md) | Stratusphere UX in Azure: preflight, the Hub, Database and Collector appliances, Connector ID Key rollout, teardown. Bicep and PowerShell for Azure Cloud Shell |
| [scripts/](scripts/Deploy-LiquidwareTier.ps1) | `Deploy-LiquidwareTier.ps1`, the one entry point for the tier (ProfileUnity, FlexApp, Stratusphere) against a landing zone. Built slice by slice; read-only so far |
| [docs/spec.md](docs/spec.md) | The tier: which product owns what, identity and storage per path, security, cost, phases ([red-team](docs/redteam.md), [decision AL-0001](docs/decisions/AL-0001-optional-tier.md)) |
| [docs/deploy-spec.md](docs/deploy-spec.md) | How the tier is deployed, end to end, by script ([red-team](docs/deploy-redteam.md), [decision AL-0002](docs/decisions/AL-0002-automated-deployment.md)) |
| [docs/console.md](docs/console.md) | The ProfileUnity console's manual steps until its silent install is verified (V18) |
| [docs/knowledge/](docs/knowledge/README.md) | The knowledge base: facts and gotchas with versions, known errors, decision records, and the sources watched to keep it current |

## The knowledge base

[docs/knowledge/](docs/knowledge/README.md) holds what this project has learned about Liquidware
products on virtual desktops in Azure, how they fit with AVD and FSLogix, and deployment gotchas, for people, tools and AI agents alike. It's one of a family of knowledge bases in the same
format ([family.yaml](docs/knowledge/family.yaml)), and it keeps itself current with GitHub Actions
alone: a weekly digest of what changed upstream, a monthly freshness check, and issue forms that turn
field reports into pull requests. Read [llms.txt](llms.txt) for a map.

Before building something, run the prior-art check (`python3 scripts/kb/prior_art.py "<topic>"`).

## Guardrails

The repo is public. Nothing in it identifies a real tenant, subscription, employer or customer,
secrets never pass through it or through chat, no Liquidware binaries or license material are
committed, and every change goes through a reviewed pull request. The full rules are in
[docs/guardrails.md](docs/guardrails.md).

## Contributing

Contributions and forks are welcome and encouraged. Fork it and make it your own, or send back what you learn: open an issue for a bug, a question or an idea, or a pull request with a fix, a test, a doc or a lesson from a real run. Small pull requests are easiest to review.

Before you open one, run the checks in [CLAUDE.md](CLAUDE.md) and [AGENTS.md](AGENTS.md) and follow the [guardrails](docs/guardrails.md). Keep tenant data, IDs and secrets out of the repo, issues and pull requests. No Liquidware binaries, license material or assessment exports, ever. By contributing, you agree your contributions are licensed under the license that covers the files you change: MIT, or Apache-2.0 for the paths [NOTICE](NOTICE) lists.

## License

MIT ([LICENSE](LICENSE)). The knowledge base tooling is adapted from sibling projects under
Apache-2.0 ([LICENSE-APACHE](LICENSE-APACHE)); [NOTICE](NOTICE) lists the paths each license covers.
