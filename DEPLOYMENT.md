# Unishield 360 Agent — Production Deployment Guide

This document describes how to build, distribute, and deploy the **Unishield 360** agent (whitelabeled Wazuh agent, v4.14.7) in production across all supported operating systems.

> **Important:** The agent is internally named `wazuh-agent` / `WazuhSvc` to stay fully compatible with the Wazuh/U360 manager. The **branding shown to users** (package metadata, installer, Add/Remove Programs, service display name) is **Unishield 360**. Do not rename internal identifiers — doing so can break manager communication, upgrades, and active-response scripts.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Repository & Source](#2-repository--source)
3. [Building Packages](#3-building-packages)
   - [3.1 Windows (.exe / .msi)](#31-windows-exe--msi)
   - [3.2 Ubuntu / Debian (.deb)](#32-ubuntu--debian-deb)
   - [3.3 RHEL / CentOS / Fedora / Amazon Linux (.rpm)](#33-rhel--centos--fedora--amazon-linux-rpm)
   - [3.4 macOS (.pkg)](#34-macos-pkg)
4. [Deploying Agents](#4-deploying-agents)
   - [4.1 Windows](#41-windows)
   - [4.2 Ubuntu / Debian](#42-ubuntu--debian)
   - [4.3 RHEL-family](#43-rhel-family)
   - [4.4 macOS](#44-macos)
5. [Enrollment & Manager Connection](#5-enrollment--manager-connection)
6. [Verification](#6-verification)
7. [Upgrading Agents](#7-upgrading-agents)
8. [Troubleshooting](#8-troubleshooting)
9. [CI/CD Pipeline (Recommended)](#9-cicd-pipeline-recommended)

---

## 1. Architecture Overview

```
┌─────────────────────┐     git clone      ┌──────────────────────────┐
│  GitHub Repository   │ ─────────────────▶ │       Build Machine      │
│  yusufcgcein/        │                    │  (Docker / native)       │
│  Unishield-Agent     │                    └────────────┬─────────────┘
└─────────────────────┘                                 │
                                                         ▼
                    ┌──────────────┬──────────────┬──────────────┬──────────────┐
                    │              │              │              │              │
                    ▼              ▼              ▼              ▼              │
             unishield-agent  wazuh-agent   wazuh-agent    unishield-agent     │
             -4.14.7.exe    _4.14.7-1_    -4.14.7-1.      -4.14.7.pkg        │
             (Windows)      amd64.deb     x86_64.rpm      (macOS)             │
                    │        (Ubuntu/Debian) (RHEL family)                    │
                    └──────────────┬──────────────┬──────────────┬────────────┘
                                   ▼
                        ┌────────────────────────┐
                        │  U360 / Wazuh Manager  │
                        │  (auto-enrollment)     │
                        └────────────────────────┘
```

- **Source + branding:** pulled from your GitHub repository.
- **Third-party libraries** (OpenSSL, curl, cJSON, etc.): downloaded during build from Wazuh's dependency server (`packages.wazuh.com/deps/...`), pinned to fixed versions.
- Each OS gets its **own native package** built from the same source.

---

## 2. Repository & Source

| Item | Value |
|---|---|
| Repository | `https://github.com/yusufcgcein/Unishield-Agent` |
| Branch | `main` |
| Base version | Wazuh **4.14.7** |
| Internal package name | `wazuh-agent` (kept for compatibility) |
| Branded display name | **Unishield 360** |

> **Security:** Make the repository **private** before production so only authorized users/build systems can pull the source.

### Layout (branding-relevant paths)

| Path | Purpose |
|---|---|
| `src/win32/` | Windows installer, icons, version resources, GUI |
| `packages/debs/SPECS/wazuh-agent/debian/` | Ubuntu/Debian package metadata |
| `packages/rpms/SPECS/wazuh-agent.spec` | RPM package metadata |
| `packages/macos/` | macOS `.pkg` build + metadata |
| `src/data_provider/` | System inventory (contains a build fix) |

---

## 3. Building Packages

### Prerequisites (any build machine)

- Linux x86_64 host with **Docker** (recommended) or native toolchain
- `git`, `make`, `gcc`, `cmake`, `python3`
- **Windows exe:** `i686-w64-mingw32` cross toolchain + `nsis`
- **macOS pkg:** requires a **Mac** with Xcode + `munkipkg`

### 3.1 Windows (.exe / .msi)

On Linux/WSL (cross-compile):

```bash
git clone https://github.com/yusufcgcein/Unishield-Agent.git
cd Unishield-Agent/src

# Install cross toolchain + NSIS (Ubuntu/WSL example)
sudo apt install gcc-mingw-w64-i686 g++-mingw-w64-i686 nsis cmake make

make deps
make TARGET=winagent -j2
```

**Output:** `src/win32/unishield-agent-4.14.7.exe`

For the MSI (WiX), build on Windows with the WiX Toolset and `src/win32/wazuh-installer.wxs`.

> **Note:** the winagent build has known quirks fixed in this repo:
> - Stale prebuilt objects must be removed before first build (see `src/Makefile` notes)
> - The `libyaml` winagent configure line and `-lbcrypt` link flag are patched
> - The NSIS `SimpleSC` plugin is replaced with `nsExec` service checks (fixes a false "already installed" prompt on Unicode NSIS builds)

### 3.2 Ubuntu / Debian (.deb)

Using the official Docker-based builder (recommended):

```bash
cd Unishield-Agent/packages
./generate_package.sh --system deb -t agent -a amd64 --sources /root/Unishield-Agent
```

Or natively (after building the agent and installing dev deps):

```bash
cd Unishield-Agent
cp -r packages/debs/SPECS/wazuh-agent/debian ./debian
debuild --rootcmd=sudo -b -uc -us
```

**Output:** `wazuh-agent_4.14.7-1_amd64.deb` (shows as **"Unishield 360 agent"**)

### 3.3 RHEL / CentOS / Fedora / Amazon Linux (.rpm)

```bash
cd Unishield-Agent/packages
./generate_package.sh --system rpm -t agent -a x86_64 --sources /root/Unishield-Agent
```

**Output:** `wazuh-agent-4.14.7-1.x86_64.rpm`

### 3.4 macOS (.pkg)

Requires a Mac with Xcode and `munkipkg`:

```bash
cd Unishield-Agent/packages/macos
./generate_wazuh_packages.sh -b v4.14.7 -a intel64    # or arm64 for Apple Silicon
```

**Output:** `unishield-agent-4.14.7-1.intel64.pkg`

---

## 4. Deploying Agents

### 4.1 Windows

1. Copy `unishield-agent-4.14.7.exe` to the target machine.
2. Double-click (or deploy via GPO/SCCM/Intune).
3. Installer shows **Unishield 360** branding; creates the `Unishield` start-menu folder.
4. Add/Remove Programs shows **Unishield 360 Agent** (Publisher: Unishield 360, Unishield 360 logo).

Silent install (enterprise):

```powershell
unishield-agent-4.14.7.exe /S
```

### 4.2 Ubuntu / Debian

```bash
sudo dpkg -i wazuh-agent_4.14.7-1_amd64.deb
# if dependency errors:
sudo apt-get install -f
```

Configure the manager address, then start:

```bash
sudo sed -i 's|<address>0.0.0.0</address>|<address>YOUR_MANAGER_IP</address>|' /var/ossec/etc/ossec.conf
sudo /var/ossec/bin/wazuh-control start
```

### 4.3 RHEL-family

```bash
sudo rpm -ivh wazuh-agent-4.14.7-1.x86_64.rpm
sudo sed -i 's|<address>0.0.0.0</address>|<address>YOUR_MANAGER_IP</address>|' /var/ossec/etc/ossec.conf
sudo /var/ossec/bin/wazuh-control start
```

### 4.4 macOS

```bash
sudo installer -pkg unishield-agent-4.14.7-1.intel64.pkg -target /
```

---

## 5. Enrollment & Manager Connection

The U360 manager has **auto-enrollment enabled** (`<use_password>no</use_password>` on the manager's `authd`).

- **No authentication key is required.** The agent registers itself automatically on first start.
- The manager issues the key; the agent stores it in `client.keys`.
- The agent reports using its own **hostname** as the default agent name.

**If your manager requires a password** (`use_password yes`), add to the agent's `ossec.conf`:

```xml
<enrollment>
  <enabled>yes</enabled>
  <manager_address>YOUR_MANAGER_IP</manager_address>
  <port>1515</port>
  <agent_name>your-agent-name</agent_name>
  <authorization_pass_path>/var/ossec/etc/authd.pass</authorization_pass_path>
</enrollment>
```

and place the registration password in `/var/ossec/etc/authd.pass`.

---

## 6. Verification

| Check | Command |
|---|---|
| Agent running | `sudo /var/ossec/bin/wazuh-control status` |
| Enrolled (has key) | `cat /var/ossec/etc/client.keys` |
| In dashboard | look for the new agent ID + name |
| Windows service | `sc query WazuhSvc` (display name: **Unishield**) |
| Add/Remove Programs | **Unishield 360 Agent**, Publisher **Unishield 360**, Unishield 360 logo |
| Linux package info | `dpkg -l | grep wazuh-agent` → **"Unishield 360 agent"** |

---

## 7. Upgrading Agents

Install the new package **over** the old one — the installer detects the existing service, stops it, upgrades, and restarts.

> **Note:** the upgrade script (`src/win32/do_upgrade.ps1`) and WPK upgrade references were updated to match the branded install layout. Test WPK upgrades in staging before production.

---

## 8. Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| Agent not connecting | Verify manager IP in `/var/ossec/etc/ossec.conf` and that ports 1514/1515 are reachable |
| "Already installed" prompt (Windows) | Fixed in this build (nsExec replaces SimpleSC); if seen on old builds, uninstall first |
| Add/Remove Programs icon blank | Use the rebuilt `.exe` (BMP-frame icons) and clear icon cache |
| No auto-enrollment | Manager `use_password` must be `no`, or configure enrollment block + password file |
| Build errors on Ubuntu 24.04 | Repo includes fixes: Berkeley DB header collision, debian/rules PATH recursion, missing dev deps (`clang`, `libelf-dev`, `zlib1g-dev`, `libexpat1-dev`, `pkg-config`) |

---

## 9. CI/CD Pipeline (Recommended)

Automate package building with GitHub Actions (Linux runner):

```yaml
name: build-agents

on:
  push:
    tags: ['v*']

jobs:
  windows:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install toolchain
        run: sudo apt install -y gcc-mingw-w64-i686 g++-mingw-w64-i686 nsis cmake make
      - name: Build
        run: |
          cd src && make deps
          make TARGET=winagent -j2
      - uses: actions/upload-artifact@v4
        with:
          name: windows-agent
          path: src/win32/unishield-agent-4.14.7.exe

  deb:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build deb
        run: |
          cd packages
          ./generate_package.sh --system deb -t agent -a amd64 --sources $GITHUB_WORKSPACE
      - uses: actions/upload-artifact@v4
        with:
          name: deb-agent
          path: packages/output/*.deb

  rpm:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build rpm
        run: |
          cd packages
          ./generate_package.sh --system rpm -t agent -a x86_64 --sources $GITHUB_WORKSPACE
      - uses: actions/upload-artifact@v4
        with:
          name: rpm-agent
          path: packages/output/*.rpm
```

**macOS** builds require a macOS runner (`runs-on: macos-latest`) and a signed Apple Developer certificate for distribution.

---

## Compliance & Licensing

- Wazuh is **GPLv2**. Whitelabeling is permitted, but:
  - Copyright/license headers in source are preserved (do not remove).
  - If you distribute binaries, the modified source must be made available under GPLv2.
  - The internal `OSSEC PASS/A/K` protocol strings are untouched to remain manager-compatible.
- **Unishield 360** trademark/logo usage is governed by your own branding policy.
