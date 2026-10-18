# Deploying the Hub from Azure Marketplace

The Hub is deployed from Liquidware's Azure Marketplace image (publisher `liquidware`, offer `stratusphere`). Three things have to line up, and the preflight checks each one.

1. **The plan (SKU) offered in your region.** Plan names are not on the public listing. `Test-StratusphereReadiness.ps1 -Location <region>` lists them (it calls `Get-AzVMImageSku`); `az vm image list-skus -l <region> -p liquidware -f stratusphere` does the same.
2. **The image carries a purchase plan.** The VM must then send a `plan` block (name, publisher, product) that matches its `imageReference`. `bicep/modules/hub.bicep` always sends one; the preflight fails early if the image has no purchase plan.
3. **The terms are accepted in the subscription.** Acceptance is per subscription and per plan, and accepting again is harmless. `deploy.sh` accepts them with `az vm image terms accept`, and the preflight's `-Fix` with `Set-AzMarketplaceTerms`. This is done in the scripts rather than in Bicep: the `Microsoft.MarketplaceOrdering` agreement resource needs the full terms record read back from Azure first, which a template can't do on its own.

If your organization blocks Marketplace purchases or limits allowed images through Azure Policy, the deployment fails at the VM. Check with whoever owns the subscription's policy before the first run.

Using Liquidware's VHD download instead of Marketplace (for subscriptions where Marketplace is blocked) is not supported yet.
