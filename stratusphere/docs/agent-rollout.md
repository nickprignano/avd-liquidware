# Connector ID Key rollout

`scripts/ops/Deploy-CidKey.ps1` runs `scripts/agent/Invoke-CidKeyAction.ps1` on Azure VMs through Run Command, several at a time, from Azure Cloud Shell. Nothing is installed on the machines except the Connector ID Key itself.

## Targets

| Parameters | Machines |
|---|---|
| `-HostPoolName -HostPoolResourceGroup` | The session hosts of an AVD host pool |
| `-ResourceGroupName [-VmName ...]` | All VMs in a resource group, or the named ones |
| `-TagName -TagValue` | VMs with a tag, across the subscription |
| `-FromReport output/cid-rollout-<time>.json` | Machines that ended failed or degraded in an earlier run |

Machines that are not Windows or not running are skipped, with the reason.

## Actions

| Action | What it does | Statuses |
|---|---|---|
| `Plan` (default) | Lists the targets and what would run. Changes nothing | |
| `Check` | Reports the key's state: healthy, degraded (and why) or absent | `present`, `degraded`, `absent` |
| `Install` | Installs. Skips machines that already have it unless `-Force` | `installed`, `already-installed` |
| `Fix` | Absent: installs. Services stopped: sets them to Automatic and starts them. Half installed (settings without the program, or the reverse): reinstalls. `-Force` reinstalls healthy keys too, for example to point them at another Hub | `repaired`, `already-healthy` |
| `Uninstall` | The installer's own `/x /s` | `uninstalled`, `absent` |
| `Cleanup` | Uninstalls with whatever uninstaller exists (MSI product code, the installer if `-InstallerUrl` is given, or the registered quiet uninstall), then removes the key's services, its settings key and its program folders. Folders are removed only under a Liquidware path | `cleaned`, `absent` |

Any machine can also end `failed`, with the reason. A run with any `failed` or `degraded` machine ends `RESULT FAIL` and prints the `-FromReport` command to rerun just those.

## The installer

The repo never ships it. Download the Connector ID Key installer from your own Hub (Hub Administration > Connector ID Keys), upload it where the machines can reach it, and pass:

- `-InstallerUrl`: an https URL, such as a blob SAS URL. Required for Install, Fix and Uninstall; optional for Cleanup.
- `-InstallerSha256`: required whenever a URL is given. Every machine checks the download against it before running it. `(Get-FileHash .\installer.exe).Hash`
- `-HubAddress`: the Hub's IP or host name, passed to the installer as `HUBADDRESS`.

Arguments are validated strictly (host name or IP, https URL without spaces or quotes, 64 hex characters) because they are embedded in the script sent to each machine.

## Hosts created later

Run Command reaches the machines that exist now. Session hosts created later from an image will not have the key: add it to the golden image (avd-landing-zone: `scripts/image/custom/Invoke-CustomImageStep.ps1`) or assign it through Intune. The agent script also runs as an Intune platform script or GPO startup script, since it is plain Windows PowerShell 5.1.

## Not yet verified on real machines

Service names (`tnt*` or a display name containing "Connector ID"), the settings key (`HKLM\SOFTWARE\Liquidware Labs\Connector ID`) and the installer's exit codes come from Liquidware's documentation, not a real run. If a run shows something different, please open an issue.

## Output

One line per machine on the console, and `output/cid-rollout-<time>.json` (git-ignored, because it holds machine names).
