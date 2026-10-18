---
title: "Known errors"
summary: "Errors hit in this project: symptom, cause, fix and source"
topic: troubleshooting
status: partial
last_reviewed: 2026-10-18
---

# Known errors

Errors we've hit, what caused them and what fixed them. The table is generated from
[known-errors.yaml](known-errors.yaml); fixes marked *(unverified)* haven't been confirmed yet.

<!-- BEGIN GENERATED: known-errors (edit the YAML, then run scripts/kb/build.py) -->
| Symptom | Cause | Fix | Source |
|---|---|---|---|
| Connector ID Keys are installed but the Hub shows no data from them | The key calls the address in its mgrcert.pem, taken from the Hub's DNS name when the installer was downloaded; the address is wrong or unreachable on TCP 443 | Set the Hub's DNS name (Configuration > Edit Network Configuration), download the installer again and reinstall, or edit mgrcert.pem and restart the key's service; allow TCP 443 from the desktops to the Hub *(unverified)* | [link](https://support.liquidware.com/hc/en-us/articles/210640563-My-Stratusphere-does-not-receive-the-data-from-systems-where-Connector-ID-is-installed) |
| Warning BCP081: Resource type "Microsoft.Network/virtualNetworks@2024-05-01" does not have types available | The installed Bicep CLI is older than the API version, so it can't check the resource's properties offline (the template still builds, and a typo would only fail at deploy) | Pin an API version the CLI knows (Microsoft.Network 2023-11-01 on Bicep 0.30), or install a newer CLI. CI installs the latest, so a local build can warn where CI doesn't | [link](https://github.com/nickprignano/avd-liquidware/blob/main/profileunity/bicep/modules/tier.bicep) |
| Error use-resource-id-functions: If property "privateLinkServiceId" represents a resource ID, it must use a symbolic resource reference, be a parameter or start with one of these functions | A resource ID passed through an array variable into a resource loop (for example a list of private endpoints and their targets) is no longer a symbolic reference, and the repo's bicepconfig.json raises this rule to an error | Loop over a small module instead, and pass each ID as a module parameter, which the rule accepts (profileunity/bicep/modules/privateEndpoint.bicep) | [link](https://github.com/nickprignano/avd-liquidware/blob/main/profileunity/bicep/modules/privateEndpoint.bicep) |
| PSUseBOMForUnicodeEncodedFile from Invoke-ScriptAnalyzer on a script that contains a section sign or an ellipsis | The file is UTF-8 without a byte order mark and holds a non-ASCII character, which Windows PowerShell 5.1 would read in the wrong code page | Keep scripts ASCII (write "section 4", three dots) rather than adding a BOM | [link](https://github.com/nickprignano/avd-liquidware/blob/main/CLAUDE.md) |
| PropertyChangeNotAllowed: Changing property 'osProfile.adminPassword' is not allowed | An incremental redeploy sends a newly generated admin password for a VM that already exists; the password is fixed at creation | Generate the password only for a new VM, and deploy the VM resource only when it doesn't exist (the tier's console module has a consoleExists condition); change a password later through the VM's reset, never by redeploy *(unverified)* | [link](https://github.com/nickprignano/avd-liquidware/blob/main/docs/deploy-spec.md) |
<!-- END GENERATED: known-errors -->

## Adding an entry

Add an entry to [known-errors.yaml](known-errors.yaml) with the exact error text as the symptom,
the versions it was seen on in `applies_to`, and a `source` (a KB page or an https link). Or open a
**Known error** issue, and a maintainer turns it into a pull request.
