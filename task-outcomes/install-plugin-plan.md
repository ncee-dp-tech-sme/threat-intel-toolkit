PROMPT: check the files in this repository and make a plan on how to install it as a plugin
DATE: Mon Nov  2 15:41:42 CET 2026

## Findings
- Repo = Claude Code plugin + single-plugin marketplace: .claude-plugin/plugin.json, .claude-plugin/marketplace.json (source "./", plugin threat-intel-toolkit v1.1.0).
- Components: agents/threat-intel-analyst.md (tools Bash/Read/Write/Glob/Grep, model sonnet), skills/threat-intel-lookup, skills/exploit-availability-check. No hooks, no MCP servers, no commands.
- Runtime: Python 3.8+ stdlib only; no API keys; fetches 10 free feeds at runtime (needs outbound HTTPS).
- Git: origin = ncee-dp-tech-sme/threat-intel-toolkit (fork), upstream = kevinmhorvath/threat-intel-toolkit.
- Uncommitted: marketplace.json owner.name changed kevinmhorvath -> ncee-dp-tech-sme; .bob/ untracked (Bob marketplace MCP config, not part of plugin).
- README install commands point at upstream (kevinmhorvath/...), not the fork.
- `claude` CLI not found on this machine; python3 3.14 present.

## Plan
1. Decide target: Claude Code (native) vs Bob (skills only, via .bob/skills).
2. Commit + push marketplace.json owner change to origin (marketplace add reads from GitHub); do not commit .bob/.
3. Update README install command to ncee-dp-tech-sme/threat-intel-toolkit (optional).
4. Install Claude Code CLI if needed. Then:
   /plugin marketplace add ncee-dp-tech-sme/threat-intel-toolkit
   /plugin install threat-intel-toolkit@threat-intel-marketplace
   Local test before push: /plugin marketplace add /Users/erwin/development/threat-intel-toolkit
5. Verify: /plugin list; /agents shows threat-intel-analyst; ask "check 45.155.205.233 and CVE-2024-3400".
6. Smoke test: python3 skills/threat-intel-lookup/scripts/healthcheck.py and skills/exploit-availability-check/scripts/healthcheck.py.
7. Bob alternative: copy skills/* to ~/.bob/skills/ (or .bob/skills/); agent file needs conversion to a Bob mode (custom_modes.yaml).
