#!/usr/bin/env python3
"""Generate / apply / remove the Threat Intel Analyst custom mode for IBM Bob.

Converts agents/threat-intel-analyst.md (Claude Code subagent format) into a Bob
custom-mode entry and manages it inside a custom_modes.yaml file between marker comments,
so re-running is idempotent and never touches other modes. Python 3.8+, stdlib only.

Usage:
  bob_mode.py apply  --file custom_modes.yaml --agent agents/threat-intel-analyst.md --skills-dir DIR
  bob_mode.py remove --file custom_modes.yaml
  bob_mode.py check  --file custom_modes.yaml        (exit 0 if managed block present)

Change log:
  Mon Nov  2 15:58:00 CET 2026  Initial version for the IBM Bob integration branch.
"""
import argparse
import json
import os
import re
import sys
import tempfile

START = "  # >>> threat-intel-toolkit (managed by scripts/install-bob.sh) >>>"
END = "  # <<< threat-intel-toolkit (managed by scripts/install-bob.sh) <<<"
SLUG = "threat-intel-analyst"
KEY_RE = re.compile(r"^customModes:\s*(\[\s*\])?\s*(#.*)?$")


# Split the agent markdown into (description, body). Mon Nov  2 15:58:00 CET 2026
def parse_agent(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValueError("agent file has no front matter")
    end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    fm, body = lines[1:end], "\n".join(lines[end + 1:]).strip()
    desc, i = "", 0
    while i < len(fm):
        if fm[i].startswith("description:"):
            first = fm[i].split(":", 1)[1].strip()
            parts = [] if first in (">-", ">", "|", "|-") else [first]
            i += 1
            while i < len(fm) and (fm[i].startswith(" ") or not fm[i].strip()):
                parts.append(fm[i].strip())
                i += 1
            desc = " ".join(p for p in parts if p)
            break
        i += 1
    return desc, body


# Build the managed YAML block (one JSON flow mapping, valid YAML). Mon Nov  2 15:58:00 CET 2026
def build_block(agent_path, skills_dir):
    desc, body = parse_agent(agent_path)
    base = skills_dir.rstrip("/")
    note = (
        "IBM Bob install note: this toolkit's skills are installed at %s. Use these absolute "
        "paths instead of the relative `skills/...` paths below: %s/threat-intel-lookup/scripts/ti.py "
        "and %s/exploit-availability-check/SKILL.md. Run scripts with python3 (stdlib only).\n\n"
        % (base, base, base)
    )
    mode = {
        "slug": SLUG,
        "name": "\U0001F6E1\uFE0F Threat Intel Analyst",
        "description": "Defensive IOC and CVE triage using free, key-free open-source threat feeds.",
        "roleDefinition": "You are a defensive threat-intelligence analyst for IOC and vulnerability triage.",
        "whenToUse": desc,
        "customInstructions": note + body,
        "groups": [
            "read",
            "command",
            ["edit", {"fileRegex": r".*\.(md|csv|json)$",
                      "description": "Triage reports (Markdown, CSV, JSON) only"}],
            "skill",
        ],
    }
    return "\n".join([START, "  - " + json.dumps(mode, ensure_ascii=False), END]) + "\n"


# Drop an existing managed block from file text. Mon Nov  2 15:58:00 CET 2026
def strip_block(text):
    out, skip = [], False
    for line in text.splitlines():
        if line.rstrip() == START:
            skip = True
            continue
        if skip and line.rstrip() == END:
            skip = False
            continue
        if not skip:
            out.append(line)
    return "\n".join(out) + ("\n" if out else "")


# Write a file atomically with private permissions. Mon Nov  2 15:58:00 CET 2026
def write_atomic(path, text):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(path)), prefix=".tmp-modes-")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


# Insert or refresh the managed block in the target file. Mon Nov  2 15:58:00 CET 2026
def apply(file, agent, skills_dir):
    block = build_block(agent, skills_dir)
    text = strip_block(open(file, encoding="utf-8").read()) if os.path.exists(file) else ""
    lines = text.splitlines()
    idx = next((i for i, l in enumerate(lines) if KEY_RE.match(l)), None)
    if idx is None:
        if any(l.startswith("customModes:") for l in lines):
            raise ValueError("unsupported inline customModes value in %s; add the mode manually" % file)
        new = (text.rstrip("\n") + "\n" if text.strip() else "") + "customModes:\n" + block
    else:
        lines[idx] = "customModes:"
        new = "\n".join(lines[: idx + 1]) + "\n" + block + "\n".join(lines[idx + 1:])
        new = new.rstrip("\n") + "\n"
    write_atomic(file, new)


# Remove the managed block; delete the file if nothing else remains. Mon Nov  2 15:58:00 CET 2026
def remove(file):
    if not os.path.exists(file):
        return
    text = strip_block(open(file, encoding="utf-8").read())
    if text.strip() in ("", "customModes:"):
        os.remove(file)
    else:
        write_atomic(file, text)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("action", choices=["apply", "remove", "check"])
    p.add_argument("--file", required=True)
    p.add_argument("--agent")
    p.add_argument("--skills-dir")
    a = p.parse_args()
    try:
        if a.action == "apply":
            if not (a.agent and a.skills_dir):
                p.error("apply needs --agent and --skills-dir")
            apply(a.file, a.agent, a.skills_dir)
        elif a.action == "remove":
            remove(a.file)
        else:
            sys.exit(0 if os.path.exists(a.file) and START in open(a.file, encoding="utf-8").read() else 1)
    except (OSError, ValueError, StopIteration) as e:
        sys.stderr.write("bob_mode.py: %s\n" % e)
        sys.exit(2)


if __name__ == "__main__":
    main()
