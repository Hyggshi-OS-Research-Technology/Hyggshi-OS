# HCL (Hyggshi Configuration Language) v1.0 — Specification Summary

`iso-config/config/config.ini` is not plain INI — it supports dependency resolution, key-driven dispatch, typed literals, and function calls. `tools/hcl_parser.py` implements these semantics directly.

## Type System

| Type       | Example                                   | Notes |
|------------|-------------------------------------------|-------|
| BOOLEAN    | `Debian = true`                           | Standard booleans (`true`/`false`) |
| STRING     | `codename = "Verdant Valley"`             | Always enclosed in double quotes `"..."` |
| NUMBER     | `timeout = 10`                            | Bare integer / float literals |
| VERSION    | `Version = 1.4.2`                         | Pattern: `\d+(\.\d+){1,3}` |
| SIZE       | `swap = false` / `1GB` / `custom > 7.2GB` | Key-specific grammar (e.g. `swap`) |
| ENUM       | `desktop = Cinnamon`, `action = run`      | Bare identifier not matching any section name |
| REFERENCE  | `base = ${Base}`                          | `${X}` dereferences another section or key |
| FUNCTION   | `fileinstall(...)`, `command(...)`        | Must match defined `FUNCTION_NAMES` |
| SECTION    | `[Base]`, `[kernel.Desktop]`              | `.` denotes subsections |
| COMMENT    | `; ...`                                   | Line or inline comments |

## Reference Resolution Rules (`Resolver`)

1. `${Name}` or bare `Name` matching a **section name**:
   - If the target section contains exclusively boolean keys: resolves to the unique key set to `true` (ENUM exclusivity). Example: `${Base}` -> `"Debian"`.
   - Otherwise: resolves to the entire section as a dictionary of resolved fields. Example: `${config-setup-postpartum-care}`.
2. Bare identifiers **not matching any section name**: treated as ENUM literals, preventing unintended cross-section key lookups.
3. The `kernel` key uses **key-driven dispatch**: its string value (e.g., `"Desktop"`) resolves to section `[kernel.Desktop]`.
4. The `firmware` key uses **key-driven dispatch**: its value points to a key in `[firmware]`, which then maps the resolved `base` to `[firmware-<Base>]` to determine which packages are set to `= true`.

## Static Validation

`Resolver.validate_every_entry()` executes `classify()` across all `key = value` entries in every section:
- Validates `SIZE` syntax (`false`, `<n>GB|MB`, `custom > <n>GB|MB`).
- Validates function names (`fileinstall`, `filecustom`, `command`, `make`, `call`).
- Validates reference integrity (`${ref}` must point to a declared section/key).
- Enforces exclusivity on `[Base]` and `[Desktop-Environment]` when matrix mode is disabled.
- Checks that file paths in `fileinstall()`, `filecustom()`, `make()`, and `command(file=...)` exist on disk relative to `--root`.
- Validates that `kernel = "X"` has a matching `[kernel.X]` section.

Run with `--strict` to exit with code 1 on any error, allowing CI to fail fast before starting container or rootfs builds.

## CLI Usage

```bash
python3 tools/hcl_parser.py iso-config/config/config.ini \
  --root . \
  --emit-json /tmp/resolved.json \
  --emit-env "$GITHUB_ENV" \
  --strict
```

### Exported Environment Variables

- `HCL_BASE_DISTRO`, `HCL_DESKTOP_ENV`, `HCL_SWAP_MB`
- `HCL_OEM_MODE`, `HCL_BUILD_ALL_OEM`, `OEM_MODE` (OEM installation mode for Calamares)
- `BUILD_NEXWM`, `NEXWM_REPO_URL` (Enabled when DE = `hde`)
- `HCL_FIRMWARE_PACKAGES`, `HCL_DESKTOP_PACKAGES`
- `HCL_APP_INSTALLS`: List of all applications declared via `fileinstall(...)`
- `HCL_PACKAGES`: List of all packages set to `= true` in `[package]` (forwarded to `EXTRA_PACKAGES` for `desktop.sh`)
- `HCL_WELCOME_SCRIPT`: First-run onboarding wizard command
- `HCL_PLYMOUTH_SCRIPT`: Plymouth boot splash script configuration
