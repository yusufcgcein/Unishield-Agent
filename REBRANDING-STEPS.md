# Rebranding Steps — Files & Modifications

## 1. Package name (Linux)

**`packages/debs/SPECS/unishield-agent/debian/control`**
- `Source:` → `unishield-agent`
- `Package:` → `unishield-agent` (all instances)
- `Maintainer:` → your company
- `Homepage:` → your domain
- `Description:` → your product

**`packages/debs/SPECS/unishield-agent/debian/changelog`**
- Package name → `unishield-agent`

**`packages/debs/SPECS/unishield-agent/debian/copyright`**
- Maintainer → your company
- Download URL → your domain

**`packages/debs/SPECS/unishield-agent/debian/rules`**
- `TARGET_DIR` → `debian/unishield-agent`
- Init script → `unishield-agent`

**`packages/rpms/SPECS/wazuh-agent.spec`**
- `Name:` → `unishield-agent`

---

## 2. Windows installer

**`src/win32/wazuh-installer.nsi`**
- `!define NAME` → `"Your Brand"`
- `!define OutFile` → `"your-brand-agent-4.14.7.exe"`
- `!define SERVICE` → **keep** `"WazuhSvc"`
- `VIAddVersionKey` lines → your brand/company/product

---

## 3. Windows PE metadata

**`src/win32/version.rc`**
- `CompanyName` → your brand
- `FileDescription` → your brand + "Agent"
- `LegalCopyright` → your brand
- `ProductName` → your brand + "Windows Agent"

---

## 4. Brand assets

**`src/win32/install.ico`** — replace with your icon
**`src/win32/uninstall.ico`** — replace with your icon
**`src/win32/favicon.ico`** — replace with your icon
**`src/win32/ui/favicon.ico`** — replace with your icon

---

## 5. Deploy page

**`deploy-agent.html`**
- `--brand` CSS variable → your brand color
- `title` → your brand + "Deploy Agent"
- `serverIp` default → your manager IP
- `MY_BASE` → your download server URL
- `PACKAGES` array → your built filenames

---

## 6. Per-customer config

**`customer.conf`**
- `MANAGER_IP` → customer's manager IP
- `MANAGER_PORT` → default `1514` (change if customer uses custom port)
- `ENROLLMENT_PORT` → default `1515`
- `VERSION` → your version
- `UNISHIELD_CERT_FILE` → signing cert path (or empty to skip signing)
- `UNISHIELD_CERT_PASS` → cert password
- `UNISHIELD_CA_NAME` → root CA name matching your cert

---

## 7. Code signing (optional)

**`sign-windows-agent.sh`** — no changes needed, reads `customer.conf`

**`src/Makefile`** (line 810) — already wired, calls `sign-windows-agent.sh`
after `makensis` when `UNISHIELD_CERT_FILE` is set

---

## 8. Agent config generation (custom ports)

**`src/init/inst-functions.sh`** — `WriteAgent()` function
- Replace hardcoded `<port>1514</port>` with `$MANAGER_PORT`
- Replace hardcoded `<enrollment><port>1515</port>` with `$ENROLLMENT_PORT`

---

## 9. Active response defaults

**`etc/templates/config/generic/ar-definitions.template`**
- Already set: firewall-drop (5763, 5710), host-deny (5763), disable-account (5720)
- Edit rules to change which attacks trigger which responses

---

## 10. Build

```bash
./build-agent.sh deb        # Linux .deb
./build-agent.sh deb 203.x  # override manager IP
./build-agent.sh win        # Windows .exe (needs mingw + nsis + osslsigncode)
```

Output: `./build-output/`

---

## What NOT to change

| Keep as-is | Reason |
|---|---|
| `WazuhSvc` service name | Manager detects agents by this name |
| `/var/ossec` install path | Agent config, logs, rules all live here |
| `src/init/inst-functions.sh` `WriteManager()` | Manager config must stay Wazuh-compatible |
| GPLv2 license headers | Legal requirement |
| All C source code | No functional changes needed for rebranding |
