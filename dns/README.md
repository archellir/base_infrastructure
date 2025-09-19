# DNS Configuration Fixes

This folder contains all DNS configuration fixes applied to resolve nameserver limit warnings and Tailscale DNS pollution.

## Problem Summary
- Tailscale was injecting 32 reverse DNS zones
- Hosting provider configured 4 DNS servers (2 IPv6 + 2 IPv4)
- Combined configuration exceeded kernel nameserver limits
- Kubernetes pods showing "Nameserver limits were exceeded" warnings

## Solution Applied
1. Disabled Tailscale DNS management
2. Reduced DNS servers to single IPv4 server
3. Disabled cloud-init network management
4. Configured systemd-resolved with strict settings
5. Restarted affected Kubernetes components

## Files in this folder
- `99-dns-fix.yaml` → `/etc/netplan/99-dns-fix.yaml`
- `dns-fix.conf` → `/etc/systemd/resolved.conf.d/dns-fix.conf`
- `99-disable-network-config.cfg` → `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg`
- `resolv.conf` → Custom resolv.conf for reference
- `tailscale-commands.txt` → Tailscale configuration commands executed

## Result
- DNS warnings eliminated for new pods
- System security improved (DNS pollution attack vector removed)
- DNS resolution fully functional
- Infrastructure stable and secure

## Verification
Run `/healthcheck` command to verify current status.