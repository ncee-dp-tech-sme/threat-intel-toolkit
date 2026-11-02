Check 45.155.205.233 and CVE-2024-3400

Mon Nov  2 16:42:20 CET 2026

## Unified Threat Intelligence & Vulnerability Triage

### 1. Indicator Triage (`threat-intel-lookup`)
- **Indicator:** `45.155.205.233`
- **Type:** IPv4
- **Verdict:** ⚪ **CLEAN** (Feeds flagging: 0)
- **Feeds Checked:** abuse.ch Feodo Tracker, Emerging Threats compromised IPs, blocklist.de, stamparm/ipsum, GreenSnow, Tor exit nodes, SANS DShield, Spamhaus DROP.
- **Analyst Note:** Not listed in public open-source threat intelligence feeds. Verify against internal firewall/flow logs and secondary platforms (VirusTotal / EDR) for active alerts.

### 2. Vulnerability Exploit Assessment (`exploit-availability-check`)
- **CVE ID:** CVE-2024-3400 (Palo Alto Networks PAN-OS GlobalProtect Command Injection)
- **Exploit Maturity:** 🔴 **Weaponized**
- **In The Wild:** CISA KEV **YES** (Added 2024-04-12; Ransomware: **KNOWN**)
- **FIRST EPSS:** 100.00% (Top 0.00% percentile)
- **Evidence:**
  - **Metasploit:** `exploit/linux/http/panos_telemetry_cmd_exec` [Rank: Excellent]
  - **Exploit-DB:** EDB-51996
  - **Nuclei:** Active critical template
  - **GitHub PoCs:** 45 repos indexed on nomi-sec (top: 162★), 122 links on trickest
- **Analyst Note:** Critical unauthenticated remote code execution vulnerability in PAN-OS with device telemetry enabled. Turnkey weaponized exploit tooling is public and actively used in wild campaigns.
