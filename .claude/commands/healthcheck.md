# Server Health Check

Performs a comprehensive security and health audit of the Kubernetes infrastructure with intelligent filtering to avoid false positives.

## Usage

```
/healthcheck
```

## Description

Executes the enhanced health check script that monitors:

**System Health:**
- System processes and resource usage (CPU, memory, disk)
- Failed systemd services
- System uptime and load averages

**Kubernetes Security:**
- Pod health and error states
- Excessive restart counts (>20, excluding network components)
- Critical Kubernetes events (filters out DNS warnings)
- Cluster node status

**Network Security:**
- Active SSH sessions and recent logins
- Unusual listening ports (excludes known K8s/service ports)
- Suspicious network processes (excludes container runtime)

**Smart Filtering:**
- Excludes false positives from container runtime processes
- Separates critical issues from informational warnings
- Accounts for normal Kubernetes operational patterns

Returns a summary with genuine anomalies flagged for investigation.

## Implementation

```bash
./scripts/healthcheck.sh
```