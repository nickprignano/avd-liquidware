---
status: proposed
date: 2026-10-18
decision-makers: [maintainers]
---

# 0003. This repo deploys the Liquidware platform; assessment and design live elsewhere

## Context and Problem Statement

The Stratusphere tooling started inside a project that also designed AVD environments from what
Stratusphere measured. Deploying the platform, running an assessment engagement, and designing a
target environment change at different speeds and serve different people. Where does each belong?

## Considered Options

- This repo deploys and operates the Liquidware platform in Azure; assessment engagements and
  target-state design are separate projects that consume it
- One repo for all three

## Decision Outcome

Chosen option: "This repo deploys and operates the platform", because the deployment tooling is
useful to anyone who runs Stratusphere in Azure, whatever they do with the data afterwards.

### Consequences

- Good, because this repo can be public and stay focused: appliances, the Connector ID Key, the
  API's behavior, Azure networking and Marketplace.
- Good, because facts about Liquidware's products live here, and other projects link to them.
- Neutral, because how an assessment is run or turned into a design isn't recorded here.
