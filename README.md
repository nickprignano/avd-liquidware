# avd-liquidware

An optional Liquidware tier for Azure Virtual Desktop: **ProfileUnity** for profile portability and user environment management, **FlexApp** packages delivered through AVD app attach, and **CommandCTRL** for real-time support. It runs against an existing landing zone, either one built by [avd-landing-zone](https://github.com/nickprignano/avd-landing-zone) or a customer's environment managed by Nerdio Manager for Enterprise. FSLogix stays the profile container.

> **Status: spec only.** Nothing is built yet. Start with [docs/spec.md](docs/spec.md), its [red-team review](docs/redteam.md) and [decision AL-0001](docs/decisions/AL-0001-optional-tier.md).

| Doc | What it covers |
|---|---|
| [docs/spec.md](docs/spec.md) | Which product owns what, architecture, identity and storage per path, security, Nerdio delivery, where CommandCTRL fits, second brain and swarm hooks, cost, facts and phases |
| [docs/redteam.md](docs/redteam.md) | Two red-team passes; every finding is folded into the spec |
| [docs/decisions/](docs/decisions/README.md) | Decision records (AL-NNNN). Plain numbers elsewhere refer to avd-landing-zone's decisions and lessons |

This is a personal project, not for production, provided as is. It is not affiliated with, endorsed by or supported by my employer, Liquidware, Nerdio or Microsoft. Liquidware, ProfileUnity, FlexApp, FlexApp One, Stratusphere and CommandCTRL are trademarks of Liquidware. Azure, Microsoft Entra, Intune and FSLogix are trademarks of Microsoft. Nerdio is a trademark of Nerdio.
