# Unishield 360 Agent — Quick Deploy

## One command to get everything

```bash
git clone https://github.com/yusufcgcein/Unishield-Agent.git && cd Unishield-Agent
```

## Pre-configured per-customer build

Each customer gets their own copy. Just set the manager IP **once** in `customer.conf`, then build.

```bash
# 1. Set the collector IP once
nano customer.conf          # edit: MANAGER_IP="your.manager.ip"

# 2. Build (output: ./build-output/)
./build-agent.sh deb        # Ubuntu/Debian .deb
./build-agent.sh rpm        # RHEL/CentOS .rpm
./build-agent.sh win        # Windows .exe
```

That's it. The manager IP is **baked into the package** — your team never touches config files on servers.

## Changing the manager IP (two ways)

### A) At build time — one build per environment

Pass the IP as a second argument — no need to edit `customer.conf`:

```bash
./build-agent.sh deb 203.0.113.10        # build for environment with IP 203.0.113.10
./build-agent.sh rpm 198.51.100.5        # another environment
./build-agent.sh deb 100.110.74.122      # etc.
```

This keeps `customer.conf` as the default, and lets you build any environment without editing files.

### B) At runtime — change IP on an already-installed agent

Point an installed agent at a different manager, without reinstalling:

**Linux / macOS:**
```bash
sudo ./set-agent-ip.sh 203.0.113.10          # or with port: sudo ./set-agent-ip.sh 203.0.113.10 1514
```

**Windows (PowerShell as Administrator):**
```powershell
.\set-agent-ip.ps1 203.0.113.10
```

The script stops the agent, updates `ossec.conf`, restarts it, and it auto re-enrolls.

## How it works

- `customer.conf` — one file, per customer: manager IP + version
- `build-agent.sh` — one command: reads the config, builds the package with that IP
- Every agent you deploy **auto-connects** to the configured manager (auto-enrollment = no key needed)

## Workflow per customer deployment

```bash
# Team member does exactly this:
git clone <your-repo> customerA && cd customerA
nano customer.conf          # set customer A's manager IP
./build-agent.sh deb
# → install ./build-output/*.deb on customer's servers
```

## Install on a server (Ubuntu/Debian)

```bash
sudo dpkg -i /path/to/wazuh-agent_4.14.7-1_amd64.deb
sudo /var/ossec/bin/wazuh-control start
```

## Install on Windows

```bash
unishield-agent-4.14.7.exe /S
```

## Platform support

| OS | Package | Command |
|---|---|---|
| Ubuntu/Debian | `.deb` | `./build-agent.sh deb` |
| RHEL/CentOS/Fedora/Amazon | `.rpm` | `./build-agent.sh rpm` |
| Windows | `.exe` | `./build-agent.sh win` |
| macOS | `.pkg` | needs a Mac (see repo `packages/macos`) |

## Verify

```bash
sudo /var/ossec/bin/wazuh-control status
cat /var/ossec/etc/client.keys        # shows your agent's enrolled key
# check the U360 dashboard for the new agent
```

## Notes

- Internal names stay `wazuh-agent` / `WazuhSvc` so everything works with the U360 manager; users see **Unishield 360** branding.
- Auto-enrollment is on by default (`use_password no` on the manager) — no auth key needed.
- GPLv2: source is whitelabeled legally; copyright headers are preserved.
