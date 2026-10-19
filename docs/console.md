# The ProfileUnity console: checklist until the silent install is verified

Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.

Everything around the console is automated: its network, the media and staging containers, its identity's roles and its local admin password (deploy-spec sections 5 and 6.1). The console software itself is installed by hand until the 6.9.5 console's silent install switches are verified (V18). `scripts/host/Install-ProfileUnityConsole.ps1` downloads the installer with the VM's own identity, checks its SHA-256 against your lock, then stops and prints this list.

Steps marked **unverified** have not been run yet; the first sandbox run checks them.

## Before: once per tier, from Cloud Shell

1. **Deploy the tier**: `./scripts/Deploy-LiquidwareTier.ps1 -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Deploy`. It creates the Key Vault and the media account the next two steps need, and warns that there is no console installer yet.
2. **Store the license string.** `./scripts/Set-LiquidwareSecret.ps1 -NamePrefix avdlz -Environment dev` prompts for it with hidden input and writes `lw-licstr` through the management plane. Never paste it anywhere else, and never into chat.
3. **Upload the console installer** you downloaded from Liquidware:
   ```powershell
   ./scripts/Publish-LiquidwareMedia.ps1 -NamePrefix avdlz -Environment dev -Path ./ProfileUnityConsole.exe -Component ProfileUnityConsole -Version 6.9.5
   ```
   It writes `output/media.lock.json`. Commit that file to the customer's private repo, never to this one.
4. **Deploy again.** The console's identity now gets its read role on `lw-licstr` (a role can only be scoped to a secret that exists), and the deploy runs `Install-ProfileUnityConsole.ps1` on the console by managed Run Command with the lock entry. Look for `PASS console-install`; a `FAIL` line carries the script's own `LW-RESULT` detail, and a hash mismatch deletes the download. The console must be running (it shuts down daily at 19:00 UTC outside prod).

## On the console

5. **Get in.** The console has no public IP, and its NSG admits 3389 only from `AzureBastionSubnet`, which the template adds with `-Bastion`. The Bastion host itself isn't built by the template yet; which SKU works against this subnet and NSG is **unverified**.
6. **Read the local admin password** (`lwadmin`, secret `lw-console-password`). The deploy gives the operator Key Vault Secrets User on that secret only. The vault is private, so read it from inside the network: an Azure Virtual Desktop session on a landing zone host, then the portal's Key Vault secrets page. That this resolves through the spoke's DNS link is **unverified**.
7. **Install** from `C:\ProgramData\avd-liquidware\media\`, following Liquidware's ProfileUnity 6.9.5 console install guide.
8. **Set the deploy path** to `C:\ProgramData\avd-liquidware\deploy`, a local folder. Never point it at the live config share: the console can't write it keylessly, and configuration reaches it only through staging and Promote (deploy-spec section 7).
9. **Enter the license.** Read it on the console with the console's own identity, so the value never crosses Cloud Shell. In Windows PowerShell on the console (replace `<vault>` with the Key Vault in `rg-avdlz-dev-liquidware`):
   ```powershell
   $t = (Invoke-RestMethod -Headers @{ Metadata = 'true' } -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net').access_token
   (Invoke-RestMethod -Headers @{ Authorization = "Bearer $t" } -Uri 'https://<vault>.vault.azure.net/secrets/lw-licstr?api-version=7.4').value | Set-Clipboard
   ```
   Paste it into the console's license field, then clear the clipboard with `Set-Clipboard -Value ' '`. Nothing is printed.
10. **Leave the Swagger API off** (off by default in 6.9.5). The second brain integration would turn it on later, reachable only from inside the tier.
11. **Sign out.** Nobody signs in to the console routinely.

## After

12. Run `./scripts/Deploy-LiquidwareTier.ps1 -NamePrefix avdlz -Environment dev -Component ProfileUnity -Action Check` from Cloud Shell.

When V18 passes, steps 5 to 11 become part of `Install-ProfileUnityConsole.ps1`, and this page shrinks to steps 1 to 4.
