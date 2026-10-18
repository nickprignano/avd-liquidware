---
status: proposed
date: 2026-10-18
decision-makers: [maintainers]
---

# 0006. Generated credentials go to Key Vault, and reruns reuse them

## Context and Problem Statement

Azure sets each appliance's admin password at creation, and the appliance keeps it. A rerun that
generated a new password would no longer match. Operators shouldn't have to remember or paste
secrets. Where does the password live?

## Considered Options

- Generate it once, store it in a Key Vault in the environment, read it back on every rerun
- Ask the operator for a password on each run
- Store it in a parameters file

## Decision Outcome

Chosen option: "Generate once, keep in Key Vault", because nobody has to remember it, it never
passes through chat or the repo, and reruns stay consistent with the appliances.

### Consequences

- Good, because secrets never leave Azure.
- Bad, because the deployer needs rights to grant themselves Key Vault read access (Owner, or
  Contributor plus User Access Administrator).
- Bad, because a lost vault means a lost password; the deploy script stops rather than generate a
  new one, and a soft-deleted vault is recovered.
