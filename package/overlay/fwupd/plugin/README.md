---
title: Plugin: systemd-pcrlock Integration
---

## Introduction

This plugin coordinates firmware updates with `systemd-pcrlock`. It temporarily
removes firmware-code predictions for system-firmware UEFI capsules and Secure
Boot policy and authority predictions for db, dbx, KEK, and PK updates.

If deployment may have started, the affected predictions remain relaxed until
the next reboot so a staged update can still boot. Failures before deployment
restore the current predictions immediately.

## Vendor ID Security

This plugin does not create a device and thus requires no vendor ID set.

## External Interface Access

This plugin executes the configured pcrlock helper, which updates pcrlock
components and restarts `systemd-pcrlock-make-policy.service`.

## Version Considerations

This plugin is specific to this NixOS configuration.
