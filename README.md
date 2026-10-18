# avd-liquidware

Automation for running **Liquidware** products in **Azure**, starting with Stratusphere UX: deploy
the appliances from Azure Marketplace, roll the Connector ID Key out to the desktops, and keep a
living knowledge base of what we learn along the way.

> [!WARNING]
> **Personal project. Not for production. No warranty.**
>
> - This is my own personal project, built on my own time. It is **not affiliated with, endorsed by or supported by my employer**, and it does not represent my employer's views, products or guidance.
> - It is **not affiliated with or endorsed by Liquidware** or Microsoft. Stratusphere is Liquidware's product; this repo only automates deploying and using it. **Bring your own Stratusphere license.**
> - It is a reference and learning project. **Do not run it in production** or against subscriptions and tenants that matter. Use a dedicated lab subscription.
> - It is provided **"as is", without warranty of any kind**. You are responsible for what it deploys, for the Azure charges it incurs, and for reviewing the code before you run it.

## What's here

| Folder | What it is |
|---|---|
| [stratusphere/](stratusphere/README.md) | Stratusphere UX in Azure: preflight, the Hub, Database and Collector appliances, Connector ID Key rollout, teardown. Bicep and PowerShell for Azure Cloud Shell |
| [docs/knowledge/](docs/knowledge/README.md) | The knowledge base: facts and gotchas with versions, known errors, decision records, and the sources watched to keep it current |

## The knowledge base

[docs/knowledge/](docs/knowledge/README.md) holds what this project has learned about Stratusphere
in Azure, for people, tools and AI agents alike. It's one of a family of knowledge bases in the same
format ([family.yaml](docs/knowledge/family.yaml)), and it keeps itself current with GitHub Actions
alone: a weekly digest of what changed upstream, a monthly freshness check, and issue forms that turn
field reports into pull requests. Read [llms.txt](llms.txt) for a map.

Before building something, run the prior-art check (`python3 scripts/kb/prior_art.py "<topic>"`).

## Guardrails

The repo is public. Nothing in it identifies a real tenant, subscription, employer or customer,
secrets never pass through it or through chat, no Liquidware binaries or license material are
committed, and every change goes through a reviewed pull request. The full rules are in
[docs/guardrails.md](docs/guardrails.md).

## License

MIT ([LICENSE](LICENSE)). The knowledge base tooling is adapted from sibling projects under
Apache-2.0 ([LICENSE-APACHE](LICENSE-APACHE)); [NOTICE](NOTICE) lists the paths each license covers.
