# ws-launcher

A PowerShell + Windows Terminal (`wt.exe`) launcher that helps you pick Git repositories (including **bare** repos with **worktrees**) and start one or more repo-defined “services” in new Git Bash tabs.

It supports:
- Scanning one or more **top directories** for Git projects
- Selecting a repo, and if it’s **bare**, selecting a **worktree**
- Loading per-repo services from `.ws-config.json` (base config in bare root + override in worktree)
- Overriding a service command via `.run-cmd` inside the selected directory
- Confirming commands before execution
- Caching scan results to speed up startup
- Optional “deep” reload to also prefetch worktrees

## Requirements

- Windows
- PowerShell 5.1+ or PowerShell 7+
- [Git for Windows] installed (`git` available on `PATH`)
- Windows Terminal installed (`wt.exe` available on `PATH`)
- Git Bash profile present in Windows Terminal (profile name must match what you configure)

## Project layout

```
ws-launcher/
├── config.ps1
├── global-config.ps1    (global.json parsing, $ref, Resolve-GlobalPath)
├── cache.ps1
├── git.ps1
├── repos.ps1
├── menu.ps1
├── launch.ps1
└── open_workspace.ps1   ← entry point
```

## Logic (how it works)

### Startup flow

1. **config.ps1** – Sets defaults: `$GitBash`, `$GitBashProfile`, `$Config.TopDirs`, `$Config.Services`, paths for cache and global.json.
2. **global-config.ps1** – If `global.json` exists (`%USERPROFILE%\.ws-launcher\global.json`):
   - Applies optional **config** overrides (GitBash, TopDirs, etc.).
   - Builds **path-based default services** (which services apply to which repo paths).
   - Resolves **definitions** and **$use** / **$ref** (see below).
3. **SearchPath** – `TopDirs` is set from (in order): CLI arguments → `$env:WS_SEARCHPATH` → config / global.json.
4. **Repo list** – From cache (if no reload) or by scanning `TopDirs` + `Config.Services`. For each repo, **global path-defaults** are re-applied so `global.json` changes apply without reload.
5. **Menu** – You pick repos (and for bare repos, a worktree), then for each chosen repo the script may show a **service** menu if multiple services are defined.
6. **Launch** – For each selected service: resolve final dir and command (including `.run-cmd`), optional confirm, then open a Windows Terminal tab (Git Bash) with that dir and command.

### global.json: definitions vs path-based services

- **definitions** – A top-level object `"definitions": { "name": "value", ... }`. It is a **lookup table only**. Names are referenced in other values with **`$use:name`** (see below). Definitions do **not** define which services belong to which path; they only provide reusable snippets (e.g. command strings).
- **Path-based services** – Every other top-level key (except `config` and `definitions`) is a **path** (absolute or relative to TopDirs). The value says which **services** apply to repos under that path:
  - **Object with `services`** – List of `{ "title", "dir", "cmd", "env"? }`. Any string in these entries can use **`$use:name`** to insert `definitions[name]`. Optional **`env`**: environment string (e.g. `SPRING_PROFILES_ACTIVE=it`) prepended to the command so you can reuse one `cmd` and vary only env (see below).
  - **Object with `$ref`** or **string** like `"$($ref:other-path)"` – This path reuses the **entire service list** of another path. Two steps: (1) take the ref and copy its services, (2) apply **overrides**. Use **`override`** with **field names** (`env`, `cmd`, `title`, `dir`) to override for **all** services: `{ "env": "($use:envIt)" }`. Use **service titles** as keys to override **only that service**: `{ "Backend": { "env": "($use:envIt)" }, "Angular": { "env": "($use:envDev)" } }`. You can combine both (global fields + per-title overrides). Backward compat: top-level **`env`** is treated as `override: { "env": "..." }`.

### global.json: reference syntax

| Syntax | Use case | Example |
|--------|----------|--------|
| **`$use:name`** | Insert a definition (snippets) in **services** or config values | `"cmd": "($use:cmdBackend)"` or `"$($use:cmdBackend) -Dprofile=dev"` |
| **`$ref:path`** | Path **reuses** another path’s service list | `"C:/git/other": "$($ref:ct-angular-ui-bare)"` or `{ "$ref": "ct-angular-ui-bare" }` |

- **`$use`** – Resolved from **definitions** (inline or whole value). Used for commands, titles, etc.
- **`$ref`** – Resolved from **path keys** (path → path). Only for the path’s value; the referenced path must have a `services` array (or its own ref resolved first).

### Service resolution precedence (per repo)

When the script needs the service list for a chosen repo/worktree:

1. **Inherited** from global.json path-defaults (if the repo path matches a path key).
2. **Bare repo root** – `<bare-repo>\.ws-config.json` (or inside `.git` if applicable).
3. **Worktree** – `<selected-worktree>\.ws-config.json` (overrides bare and inherited).

So: **worktree .ws-config** overrides **bare root .ws-config** overrides **global.json path-defaults**. Definitions and `$use` are resolved when building those defaults; they are not a separate “extension” layer.

**Debug:** Run with **`-Verbose`** to print the resolved global.json (definitions and path-defaults after `$use` / `$ref` / override resolution), e.g. `.\open_workspace.ps1 -Verbose`.

### Optional `env` on services (vary only environment)

To avoid repeating the same command when only the environment changes, use **`env`** on the service and keep **`cmd`** in definitions:

- In **definitions**: e.g. `"cmdBackend": "mvn spring-boot:run"`, `"envIt": "SPRING_PROFILES_ACTIVE=it"`.
- In a **service**: `{ "title": "Backend (IT)", "dir": ".", "cmd": "($use:cmdBackend)", "env": "($use:envIt)" }`.

The launcher runs the shell command as `env_string cmd`, so the effective command is `SPRING_PROFILES_ACTIVE=it mvn spring-boot:run`. You define the command once and only vary `env` per profile/variant.

## Quick start

1. Put the files in a folder (e.g. `C:\tools\ws-launcher\`)
2. Edit `config.ps1`:
   - `$GitBash` path (if needed)
   - `$Config.TopDirs` (folders containing your repos)
3. Run:

```powershell
.\open_workspace.ps1
```

You will get an interactive menu:
- **UP/DOWN** to move
- **SPACE** to toggle selection
- **ENTER** to confirm
- **ESC** to cancel

Repo menu shortcuts:
- `T` toggles repo mode between **[RUN]** and **[OPEN]**
- `R` rescans worktrees for the highlighted **bare** repo (updates cache)
- `W` opens worktree management menu for the highlighted **bare** repo (add/remove worktrees)
- `E` opens executable launcher for the highlighted repo (launches executables from config)

## Command-line arguments

### TopDirs override

You can override scan locations without editing `config.ps1`:

```powershell
.\open_workspace.ps1 "C:\git" "D:\src"
```

### Reload behavior

The launcher writes a cache file to:

- `%USERPROFILE%\.ws-launcher-cache.json`

Reload modes:

- Default (no reload): **use cache** if present, otherwise scan.
- Shallow reload: **rescan repos** but do **not** prefetch worktrees.
- Deep reload: rescan repos and **prefetch worktrees** for bare repos.

Examples:

```powershell
# use cache (fast)
.\open_workspace.ps1

# rescan repos, skip worktree prefetch (fast-ish)
.\open_workspace.ps1 -Reload

# rescan repos + prefetch all worktrees for bare repos (slow)
.\open_workspace.ps1 -Reload deep
```

> Note: even in shallow mode, if you pick a bare repo, worktrees will be fetched on-demand at that moment.

## Per-repo configuration: `.ws-config.json`

Each repository can define one or more services in `.ws-config.json`.

### Where it is read from

- If the repo is **bare**:
  - base config: `<bare-repo>\.ws-config.json`
  - override config: `<selected-worktree>\.ws-config.json`
- If the repo is **non-bare**:
  - only the worktree config is relevant (it’s just the repo root)

### Schema

```json
{
  "services": [
    {
      "title": "Spring Boot",
      "dir": ".",
      "cmd": "mvn21 spring-boot:run -Dskip.npm"
    },
    {
      "title": "Angular",
      "dir": "src/angular",
      "cmd": "npm run local"
    }
  ]
}
```

Notes:
- `title` is shown in menus and used as the merge key when overriding.
- `dir` is relative to the selected worktree base directory.
- If `dir` doesn’t exist, the launcher falls back to the **worktree base dir**.

- Optional **`env`**: string prepended to `cmd` when running (e.g. `SPRING_PROFILES_ACTIVE=it`), so you can reuse the same command with different env.

### Executable configuration

You can also define a list of executables to launch from your repository:

```json
{
  "services": [...],
  "executables": [
    {
      "name": "My Application",
      "path": "bin/myapp.exe"
    },
    {
      "name": "Database Tool",
      "path": "tools/db-client.exe"
    }
  ]
}
```

Notes:
- `name` is shown in the executable selection menu
- `path` is relative to the repository/worktree root (or absolute)
- Press `E` on any repo in the main menu to open the executable launcher
- For bare repos, you'll be prompted to select a worktree first

### Merge rules (bare repos)

If both bare-root and worktree override config exist:
- Services are merged by `title`
- Override config only replaces fields that are present and non-empty:
  - `dir` overrides `dir`
  - `cmd` overrides `cmd`

## Local command override: `.run-cmd`

If a file named `.run-cmd` exists in the **final directory** being launched (worktree root or service dir), its contents override the configured `cmd`.

Example:

`C:\git\myrepo\.run-cmd`
```
npm run dev
```

Rules:
- Leading/trailing whitespace is trimmed
- Empty file => ignored

## Execution confirmation

If the repo is in **[RUN]** mode and there is a command to run:
- The script shows the directory and command
- You must press `Y` to execute

If in **[RUN]** mode but no command is found:
- You can press `Y` to open a tab in that directory instead
- Or `N`/`ESC` to skip

## Config reference (`config.ps1`)

### Git Bash path

Update if your Git is installed elsewhere:

- Default:
  - `C:\Program Files\Git\bin\bash.exe`

### Windows Terminal profile name

The script uses:

- `wt.exe ... -p "Git Bash"`

If your profile name differs, update `launch.ps1` accordingly.

### TopDirs

`$Config.TopDirs` should contain directories that directly contain repo folders.

Example:

```powershell
$Config = [ordered]@{
  TopDirs  = @( "C:\git\ct", "D:\src" )
  Services = @()
}
```

### Explicit Services (optional)

`$Config.Services` can be used to pin specific repos (including ones outside TopDirs).
Each should have: `Title`, `Dir`, `Cmd`, `Exec`.

Example:

```powershell
$Config.Services = @(
  @{ Title="my-repo"; Dir="D:\work\my-repo"; Cmd=""; Exec=$true }
)
```

## Worktree Management

The launcher now includes built-in worktree management for bare repositories.

### Adding worktrees

1. Select a bare repo in the main menu
2. Press `W` to open the worktree management menu
3. Select "Add New Worktree"
4. Enter the branch name (new or existing)
5. Confirm the worktree creation

The launcher will:
- Create a new worktree in a subdirectory of the bare repo
- Create a new branch if it doesn't exist
- Automatically set up the upstream branch for pushing

### Removing worktrees

1. Select a bare repo in the main menu
2. Press `W` to open the worktree management menu
3. Select "Remove Existing Worktree"
4. Select the worktree to remove from the list
5. Confirm the removal

The worktree directory and its association with the bare repo will be removed.

## Troubleshooting

### Worktrees not showing
- Ensure the repo is actually bare and has worktrees:
  - `git -C <bare-repo> worktree list`
- Use `R` on the repo in the selection menu to rescan worktrees
- Or run with deep reload:
  - `.\open_workspace.ps1 -Reload deep`

### `wt.exe` not found
- Install Windows Terminal
- Ensure `wt.exe` is on PATH (usually is after install)

### `git` not found
- Install Git for Windows and ensure `git.exe` is on PATH

### UTF-8 / weird characters
The UI uses plain ASCII hints (e.g. `[UP/DOWN]`) to avoid Unicode parsing issues in some PowerShell environments.
