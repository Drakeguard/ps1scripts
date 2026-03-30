# ws-launcher

PowerShell launcher for **Windows Terminal** (`wt.exe`): pick Git repos (including **bare** repos and **worktrees**), start **services** in new Git Bash tabs, optionally run **per-repo executables**, open **global shortcut apps**, or open the project folder in an **IDE** (default: VS Code `code`).

**Features**

- Scan one or more **top directories** for repos; optional pinned entries via `Services`
- **Services** from `global.json` path defaults and/or per-repo `.ws-config.json`; optional `.run-cmd` override
- **Executables** in `.ws-config.json` (per repo/worktree); **applications** list in `global.json` (any app, with optional CLI args)
- **IDE**: open repo or selected worktree folder via configurable CLI (e.g. `code`)
- Launch confirmation in **[RUN]** mode, **cache** for faster restarts, **deep** reload to prefetch worktrees

## Requirements

- Windows  
- PowerShell 5.1+ or 7+  
- [Git for Windows](https://git-scm.com/download/win) (`git` on `PATH`)  
- Windows Terminal (`wt.exe` on `PATH`)  
- A Windows Terminal profile for Git Bash whose **name** matches `$GitBashProfile` (see `config.ps1` or `global.json`)

## Quick start

1. Clone or copy this folder (e.g. `C:\tools\ws-launcher\`).
2. Edit **`config.ps1`**: `$GitBash`, `$Config.TopDirs`, and optionally `$GitBashProfile`.
3. Run:

```powershell
.\open_workspace.ps1
```

Optional: copy **`samples/global.json`** to `%USERPROFILE%\.ws-launcher\global.json`, and use **`samples/.ws-config.example.json`** as a template for per-repo `.ws-config.json`.

## Project layout

```
ws-launcher/
├── open_workspace.ps1   ← entry point
├── config.ps1
├── global-config.ps1
├── cache.ps1
├── git.ps1
├── repos.ps1
├── executables.ps1
├── ide.ps1
├── menu.ps1
├── launch.ps1
└── samples/             ← global.json + .ws-config.example.json
```

## How it works

1. **`config.ps1`** – Defaults: Git Bash paths, `$Config` (TopDirs, Services, Applications, IDE), `global.json` and cache paths.
2. **`global-config.ps1`** – If `%USERPROFILE%\.ws-launcher\global.json` exists: merge **config** (TopDirs, Services, **applications**, **ide**, …), resolve **definitions** / **`$use`** / **`$ref`**, build path-based **service** defaults.
3. **Search path** – TopDirs from: CLI args → `$env:WS_SEARCHPATH` → config / `global.json`.
4. **Repo list** – Cache (unless reload) or scan TopDirs + `Config.Services`; global path defaults re-attached each run.
5. **Menu** – Multi-select repos; bare repos may need a worktree when launching.
6. **Launch** – For each repo: service menu if needed, then Git Bash tabs (or directory-only in **[OPEN]** mode).

**Verbose:** `.\open_workspace.ps1 -Verbose` prints resolved global path defaults.

## `global.json`

**Location:** `%USERPROFILE%\.ws-launcher\global.json`

### `config` block

Overrides the same ideas as `config.ps1`, for example:

| Key | Purpose |
|-----|--------|
| `GitBash`, `GitBashProfile` | Bash executable and WT profile name |
| `TopDirs` | Directories whose **immediate child folders** are scanned for repos |
| `Services` | Extra fixed repo entries (see below) |
| `applications` | Global app shortcuts (see **Global applications**) |
| `ide` | IDE CLI for **V** (see **IDE**) |

Strings can use **`$use:name`** with top-level **`definitions`**.

### Path keys (default services)

Any top-level key other than `config` and `definitions` is treated as a **path** (absolute or relative to TopDirs). Its value describes **services** for repos under that path:

- `{ "services": [ … ] }` – list of `{ "title", "dir", "cmd", "env"? }`
- `{ "$ref": "other-path-key", "override": { … } }` or `"$($ref:other-path-key)"` – reuse another path’s services and optionally override

**`$use` / `$ref`**

| Syntax | Meaning |
|--------|--------|
| `($use:name)` or `$($use:name)` | Insert `definitions[name]` |
| `$($ref:pathKey)` or `{ "$ref": "pathKey", … }` | Reuse services from another path key |

### Service list resolution (order)

When launching a repo, the **services** list is built in this order; **each step replaces the whole list** if it defines `services`:

1. Inherited from `global.json` path match (`DefaultConfig`)
2. Bare repo root `.ws-config.json` (and/or under `.git` when applicable)
3. Selected worktree `.ws-config.json` (wins over bare root)

### Optional `env` on services

`env` is a string prepended to `cmd` in the shell (e.g. `SPRING_PROFILES_ACTIVE=it mvn spring-boot:run`).

---

### Global applications

Under **`config.applications`** (or **`Applications`**), an array of objects:

```json
"applications": [
  { "name": "KeePass", "path": "C:\\Program Files\\KeePass\\KeePass.exe" },
  {
    "name": "VS Code",
    "path": "C:\\...\\Code.exe",
    "arguments": ["--new-window"],
    "workingDirectory": "C:\\git"
  }
]
```

- **`path`** – absolute or relative (resolved from the process working directory when launching from the menu; prefer absolute for global apps)
- **`arguments`** – optional string or JSON array (`arguments`, `Arguments`, `args`, `Args` are accepted)
- **`workingDirectory`** – optional; default is the executable’s directory

In the repo menu, press **`G`** to open this list. From the shell:

```powershell
.\open_workspace.ps1 -Apps
```

### IDE (open folder)

Under **`config.ide`**:

```json
"ide": { "command": "code", "arguments": ["--new-window"] }
```

Shorthand: `"ide": "code"`. Use **`command`** or **`executable`**. Extra CLI tokens go in **`arguments`** (before the folder path). Requires the IDE CLI on `PATH` (e.g. VS Code “Install `code` command”).

In the repo menu, press **`V`** to open the **highlighted** repo (or chosen worktree if bare) in the IDE.

## Interactive menu

| Key | Action |
|-----|--------|
| ↑ / ↓ | Move |
| Space | Toggle selection (multi-select) |
| Enter | Confirm |
| Esc | Cancel |
| **A** | Select / clear all |
| **T** | Toggle **[RUN]** / **[OPEN]** for current row |
| **R** | Rescan worktrees (bare repo), refresh cache |
| **W** | Worktree add/remove (bare repo) |
| **V** | Open current repo/worktree in IDE |
| **E** | Per-repo **executables** from `.ws-config.json` |
| **G** | **Global applications** from `global.json` |

## Command line

```powershell
# Override TopDirs
.\open_workspace.ps1 "C:\git" "D:\src"

# Reload: "" = fast default; "fast" = rescan; "deep" = rescan + prefetch worktrees
.\open_workspace.ps1 -Reload
.\open_workspace.ps1 -Reload deep

# Windows Terminal profile name (Git Bash tab)
.\open_workspace.ps1 -Profile "Git Bash"

# Only global applications menu, then exit
.\open_workspace.ps1 -Apps
```

## Paths on disk

| Item | Path |
|------|------|
| Global config | `%USERPROFILE%\.ws-launcher\global.json` |
| Scan cache | `%USERPROFILE%\.ws-launcher\cache.json` |
| Per-repo config | `.ws-config.json` (bare root and/or worktree) |

## `.ws-config.json` (per repo)

### `services`

```json
{
  "services": [
    { "title": "Backend", "dir": ".", "cmd": "mvn spring-boot:run" },
    { "title": "Frontend", "dir": "src/web", "cmd": "npm run dev", "env": "NODE_ENV=development" }
  ]
}
```

- **`title`** – Menu label  
- **`dir`** – Relative to the selected worktree root; if missing on disk, the launcher uses the worktree root  
- **`cmd`** – Command run in Git Bash  
- **`env`** – Optional; prepended to `cmd`

### `executables`

Press **E** on a repo. Same shape as global **applications**: **`name`**, **`path`** (relative to repo/worktree or absolute), optional **`arguments`**, **`workingDirectory`**.

```json
"executables": [
  { "name": "App", "path": "bin\\app.exe" },
  { "name": "Tool", "path": "tools\\x.exe", "arguments": ["--config", "app.json"] }
]
```

Bare repo: you pick a worktree first; paths are relative to that worktree.

## `.run-cmd` override

If **`.run-cmd`** exists in the **final service directory** (after resolving `dir`), its first non-empty line replaces that service’s `cmd` (trimmed whitespace).

## Launch confirmation

In **[RUN]** mode, before running a non-empty command, the script asks **Y** to run or **N** / Esc to skip. If there is no command, **Y** can still open a tab in that directory.

## `config.ps1` reference

- **`$GitBash`** – Path to `bash.exe`  
- **`$GitBashProfile`** – Windows Terminal profile name passed to `wt.exe -p`  
- **`$Config.TopDirs`** – List of root folders to scan (each entry can be a string path or `@{ path = "..."; defaultConfig = … }`)  
- **`$Config.Services`** – Optional pinned repos: `Title`, `Dir`, `Cmd`, `Exec`  
- **`$Config.Applications`** – Default empty; usually filled from `global.json`  
- **`$Config.IdeCommand`** / **`$Config.IdeArguments`** – Default `code` / `@()`; override via `global.json` **`ide`**

## Worktrees (bare repos)

**W** opens add/remove flows: new worktree under the bare repo root, or remove an existing linked worktree. After changes, **R** refreshes the cached list.

## Troubleshooting

- **Worktrees missing** – `git -C <bare-repo> worktree list`; **R** in the menu; or `-Reload deep`.  
- **`wt.exe` / `git` not found** – Install and ensure `PATH`.  
- **Hints use ASCII** – Avoids encoding issues in some consoles.
