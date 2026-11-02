# Installing the Threat Intel Toolkit in IBM Bob

A step-by-step guide for people who do **not** need to be technical. Follow the steps in order.
Everything is done with one copy-and-paste installer. Nothing needs an account, an API key or a
password.

**Contents**

1. [What you get](#1-what-you-get)
2. [What you need first](#2-what-you-need-first)
3. [Install in 3 steps](#3-install-in-3-steps)
4. [Try it](#4-try-it)
5. [Where the code comes from: fork vs original](#5-where-the-code-comes-from-fork-vs-original)
6. [Switching between the fork and the original](#6-switching-between-the-fork-and-the-original)
7. [Updating, undoing and removing](#7-updating-undoing-and-removing)
8. [Optional settings](#8-optional-settings)
9. [Troubleshooting](#9-troubleshooting)
10. [Manual install (no script)](#10-manual-install-no-script)
11. [How it works (for the curious)](#11-how-it-works-for-the-curious)

---

## 1. What you get

| Piece | What it does in Bob |
|---|---|
| Skill `threat-intel-lookup` | Checks IP addresses, domains, URLs and CVEs against 10 free threat feeds |
| Skill `exploit-availability-check` | Tells you how ready-made the exploit tools for a CVE are |
| Mode **Threat Intel Analyst** | A Bob mode that picks the right skill for you and explains the result |

It only reads public information. It never scans or contacts the things you ask about.

## 2. What you need first

| Need | How to check | If missing |
|---|---|---|
| IBM Bob installed | Open Bob, or type `bob --version` in a terminal | Install Bob from your IBM source |
| Python 3.8 or newer | Type `python3 --version` | <https://www.python.org/downloads/> |
| Git | Type `git --version` | <https://git-scm.com/downloads>. On a Mac, type `xcode-select --install` |
| Internet access (HTTPS) | Open <https://github.com> in a browser | Ask your network team to allow it |

**How to open a terminal:** on a Mac press `Cmd + Space`, type `Terminal`, press Enter. On Windows
use *WSL* or *Git Bash* (the installer is a shell script). On Linux open your terminal app.

No other software or `pip install` is needed: the toolkit uses only what Python already includes.

## 3. Install in 3 steps

**Step 1 - Download the toolkit** (from the fork):

```bash
git clone https://github.com/ncee-dp-tech-sme/threat-intel-toolkit.git
cd threat-intel-toolkit
```

> The installer script lives on the integration branch until it is merged. If `scripts/install-bob.sh`
> is missing, run `git checkout feature/ibm-bob-integration` first.

**Step 2 - Preview (changes nothing):**

```bash
scripts/install-bob.sh install --dry-run
```

It prints what it would do, including a risk note. Nothing is changed.

**Step 3 - Install:**

```bash
scripts/install-bob.sh install
```

Type `y` and press Enter when asked (`a` = "always allow", remembered for next time). The script:

1. checks Python and Git,
2. downloads the toolkit from the fork,
3. backs up anything it would replace,
4. copies the two skills and adds the **Threat Intel Analyst** mode to Bob,
5. checks that everything works,
6. downloads the public threat feeds (about 13 seconds).

Finally, **restart IBM Bob** (close and reopen it, or reload the window).

Installing for one project only? Add `--project-dir /path/to/your/project`.

## 4. Try it

In Bob, choose the **Threat Intel Analyst** mode and type:

> Check 45.155.205.233 and CVE-2024-3400

Bob should answer with a verdict per item (for example MALICIOUS, EXPLOITED, SUSPICIOUS or CLEAN)
and which feeds flagged it. *CLEAN never means "safe"* - it only means no free feed lists it.

Quick health check from the terminal at any time:

```bash
scripts/install-bob.sh check
```

## 5. Where the code comes from: fork vs original

| Name | Address | Use it when |
|---|---|---|
| **Fork** (default) | `https://github.com/ncee-dp-tech-sme/threat-intel-toolkit` | You want this team's version, including the Bob installer |
| **Original / upstream** | `https://github.com/kevinmhorvath/threat-intel-toolkit` | You want the author's untouched version |

Both addresses are stored in one place, the settings file `.env` (created from
[`.env.example`](../.env.example)). They are never hidden in code, so you can change them without
editing scripts.

## 6. Switching between the fork and the original

```bash
scripts/install-bob.sh switch upstream    # use the original repository
scripts/install-bob.sh switch fork        # go back to the fork
scripts/install-bob.sh switch https://github.com/someone/other-fork.git   # any other https repo
scripts/install-bob.sh status             # which one is installed right now?
```

Each switch backs up what is installed, reinstalls from the chosen source and remembers your
choice in `.env`. To install a specific branch or release, add `--ref NAME`, for example
`scripts/install-bob.sh install --ref v1.1.0`.

If the switch is not what you wanted, run `scripts/install-bob.sh rollback` to return to the
previous state.

> **Developers:** the git remotes of a clone follow the same idea. `origin` = fork, `upstream` =
> original. Compare with `git fetch upstream && git log main..upstream/main`. Pull original changes
> with `git merge upstream/main`.

## 7. Updating, undoing and removing

| I want to... | Run |
|---|---|
| Get the latest version from the same source | `scripts/install-bob.sh update` |
| Undo the last install, switch or uninstall | `scripts/install-bob.sh rollback` |
| Remove the toolkit from Bob | `scripts/install-bob.sh uninstall` |
| See what is installed and from where | `scripts/install-bob.sh status` |
| Add `--yes` to skip the question | `scripts/install-bob.sh update --yes` |

Backups are kept in `~/.bob/backups/threat-intel-toolkit/` (the 5 newest). Uninstall removes only
this toolkit's two skills and its own block in Bob's mode file. Your other modes and settings are
not touched. The downloaded feed data lives in `~/.cache/ti-aggregator` and
`~/.cache/exploit-availability-check`; delete those folders if you want it gone too.

## 8. Optional settings

Copy the template once and edit it with any text editor:

```bash
cp .env.example .env
```

| Setting | Meaning | Default |
|---|---|---|
| `TI_SOURCE` | `fork`, `upstream` or `custom` | `fork` |
| `TI_FORK_URL` / `TI_UPSTREAM_URL` / `TI_CUSTOM_URL` | Repository addresses (https only) | see file |
| `TI_REF` | Branch or tag to install | `main` |
| `TI_SCOPE` | `global` (all projects) or `project` | `global` |
| `TI_PROJECT_DIR` | Project folder for project scope | empty |
| `TI_BUILD_CACHE` | Download feeds right after installing | `true` |
| `BOB_HOME` | Bob's settings folder | `~/.bob` |
| `LOG_LEVEL` | `DEBUG`, `INFO`, `WARN`, `ERROR` | `INFO` |

`.env` is private to your computer and is never uploaded (it is git-ignored). It holds no secrets.
The installer log is `~/.bob/logs/threat-intel-install.log`.

## 9. Troubleshooting

| What you see | Why | Fix |
|---|---|---|
| `command not found: git` or `python3` | Not installed | Install from the links in [section 2](#2-what-you-need-first), then run again |
| `Permission denied` when running the script | Script not marked runnable | `chmod +x scripts/install-bob.sh` or run `bash scripts/install-bob.sh install` |
| `scripts/install-bob.sh: No such file` | You are on the wrong branch or folder | `cd threat-intel-toolkit` then `git checkout feature/ibm-bob-integration` |
| `Download failed` | No internet, proxy, wrong URL or branch | Open the repository address in a browser. Check `TI_FORK_URL` / `--ref`. Behind a proxy: `git config --global http.proxy http://proxy:port` |
| `Not an allowed repository URL` | URL is not plain `https://host/owner/repo` (or contains a password) | Use a plain https address with no username or password |
| `CERTIFICATE_VERIFY_FAILED` while building the cache | Python on macOS has no certificates yet | Run `/Applications/Python\ 3.*/Install\ Certificates.command` (python.org installs), then `scripts/install-bob.sh update`. On a corporate network with TLS inspection, ask IT for the company root certificate and set `SSL_CERT_FILE=/path/to/ca.pem`. Do **not** turn verification off |
| `Cache build failed` | Offline or feeds blocked | Harmless. Install still worked. Later ask Bob: "refresh the threat feed cache", or run `python3 ~/.bob/skills/threat-intel-lookup/scripts/ti.py aggregate` |
| Mode "Threat Intel Analyst" not in Bob | Bob not restarted, or project scope used elsewhere | Restart Bob. Run `scripts/install-bob.sh status` to see the install location |
| Skills not listed in Bob settings | Bob reads `~/.bob/skills` (all projects) or `<project>/.bob/skills` | Check with `status`. Open the project that you installed into |
| `Could not update ...custom_modes.yaml` | The file has an unusual format | Nothing is changed (auto-restored). Use the [manual install](#10-manual-install-no-script) |
| Something went wrong and I want it as before | | `scripts/install-bob.sh rollback` |
| No answer for a file hash | Hashes are not covered (they need API keys) | Use VirusTotal or your EDR |

Still stuck? Run `scripts/install-bob.sh check` and `LOG_LEVEL=DEBUG scripts/install-bob.sh install --dry-run`,
then open an issue at <https://github.com/ncee-dp-tech-sme/threat-intel-toolkit/issues> and attach
the last lines of `~/.bob/logs/threat-intel-install.log` (it contains no secrets).

## 10. Manual install (no script)

1. Download the repository as a ZIP from the fork's GitHub page and unzip it.
2. Copy the folders `skills/threat-intel-lookup` and `skills/exploit-availability-check` into
   `~/.bob/skills/` (all projects) or `<your project>/.bob/skills/` (one project). Create
   `skills` if it does not exist.
3. Restart Bob. The two skills now appear in **Settings > Skills**.
4. (Optional) The analyst mode: run
   `python3 scripts/bob_mode.py apply --file ~/.bob/settings/custom_modes.yaml --agent agents/threat-intel-analyst.md --skills-dir ~/.bob/skills`.

## 11. How it works (for the curious)

- The repository is a Claude Code plugin. Bob uses the same `SKILL.md` skill format, so the two
  skills are copied unchanged into Bob's `skills` folder.
- The "agent" file `agents/threat-intel-analyst.md` is a Claude Code format. Bob uses *modes*, so
  [`scripts/bob_mode.py`](../scripts/bob_mode.py) converts it into a mode entry in `custom_modes.yaml`.
  The entry sits between two marker comments, so reinstalling replaces only that block and
  uninstalling removes only that block.
- The mode may read files, run commands, use skills, and edit only `.md`, `.csv` and `.json`
  files (for saved reports).
- There are no third-party dependencies, so there is no `requirements.txt`. Python's standard
  library is enough.
- Safety: the installer only accepts plain `https://` repository addresses, never runs the `.env`
  file as code, always backs up before changing, restores automatically if a step fails, and never
  turns off certificate checking.
