---
title: "Connector ID Key"
summary: "The Stratusphere agent on each desktop: installer switches, callbacks to the Hub, where its services and settings live, and images created later"
topic: stratusphere
status: partial
last_reviewed: 2026-10-18
sources:
  - https://support.liquidware.com/hc/en-us/articles/210640563-My-Stratusphere-does-not-receive-the-data-from-systems-where-Connector-ID-is-installed
  - https://support.liquidware.com/hc/en-us/articles/210640503-Where-are-all-the-Stratusphere-Connector-ID-settings-are-stored-on-the-system
---

# Connector ID Key

The Connector ID Key is Stratusphere's agent on each desktop. It calls back to the Hub (or a
Collector) with what it measures. This repo rolls it out with
[`Deploy-CidKey.ps1`](../../../stratusphere/docs/agent-rollout.md); this page holds the facts.
Items marked *unverified* haven't been confirmed on real machines yet; the rest cite Liquidware's
support center.

## Installer

- Download it from your own Hub (Hub Administration > Connector ID Keys). It's never stored in this
  repo.
- Silent install: `<installer>.exe /s HUBADDRESS=<hub-fqdn-or-ip>` *(unverified)*.
- Silent uninstall: `<installer>.exe /x /s` *(unverified)*.
- The MSI is meant for Group Policy deployment; scripted installs use the EXE *(unverified)*.
- Exit codes are *unverified*.

## On the machine

- Services: names starting `tnt`, or a display name containing "Connector ID" *(unverified)*.
- Settings key: `HKLM\SOFTWARE\Liquidware Labs\Connector ID` *(unverified)*.

- Program folder: `C:\Program Files (x86)\Liquidware Labs\Connector ID`. A `ca\cert.txt` file there
  means the key received its first instructions from the Hub
  ([support article](https://support.liquidware.com/hc/en-us/articles/210640503-Where-are-all-the-Stratusphere-Connector-ID-settings-are-stored-on-the-system)).

## Callbacks

The key calls the Hub on TCP 443. An NSG or firewall between the desktops and the Hub must allow it
([azure/networking.md](../azure/networking.md)).

- The address it calls is the first line of `ca\public\mgrcert.pem` in the program folder. It
  comes from the Hub's DNS name (Configuration > Edit Network Configuration) when the installer was
  downloaded, so set the Hub's DNS name before downloading the installer. A key with the wrong
  address needs reinstalling from a fresh download, or `mgrcert.pem` edited and its service
  restarted
  ([support article](https://support.liquidware.com/hc/en-us/articles/210640563-My-Stratusphere-does-not-receive-the-data-from-systems-where-Connector-ID-is-installed)).
- Desktops that can't reach the Hub can register with a CID Collector instead (Stratusphere 6.5.1
  or later for the simplest route) *(unverified)*.

## Desktops created later

Azure Run Command reaches only the machines that exist when it runs. Session hosts created later
from an image need the key in the golden image, or an Intune or Group Policy assignment. The image
side belongs to the AVD knowledge base ([family.yaml](../family.yaml)).
