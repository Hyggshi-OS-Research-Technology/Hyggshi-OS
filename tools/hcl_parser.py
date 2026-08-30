#!/usr/bin/env python3
"""
hcl_parser.py — Parser + Resolver + Validator cho Hyggshi Configuration
Language (HCL) v1.0.

File .ini của Hyggshi OS (iso-config/config/config.ini) không phải INI
thuần: nó có reference resolution (${Base}), key-driven dispatch
(kernel = "Desktop" -> [kernel.Desktop]), typed literals (SIZE: 1GB /
custom > 7.2GB), và function calls (fileinstall(), filecustom(),
command(...), make()). Script này parse toàn bộ thành AST, resolve hết
reference/function, validate, rồi xuất:

  1. JSON đã resolve hoàn chỉnh (để debug / cho tool khác đọc)
  2. File env (KEY=VALUE) tương thích $GITHUB_ENV để build.sh source

Dùng:
    python3 hcl_parser.py path/to/config.ini \
        --root . \
        --emit-json resolved.json \
        --emit-env build.env \
        --strict

--strict: bất kỳ lỗi validate nào cũng exit(1) — dùng trong CI để build
fail sớm thay vì chạy nửa chừng rồi lỗi khó hiểu ở bước sau.

Không phụ thuộc thư viện ngoài (chỉ stdlib) để chạy được thẳng trong
runner GitHub Actions không cần pip install.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# 1. TYPE SYSTEM
# ---------------------------------------------------------------------------
# HCL 1.0 kiểu dữ liệu: BOOLEAN, STRING, NUMBER, VERSION, SIZE, ENUM,
# REFERENCE, FUNCTION, SECTION, COMMENT.

SIZE_KEYS = {"swap"}  # các key được parse theo grammar SIZE thay vì BOOLEAN

# PATCH: thêm filetheme/filecopy — dùng trong block "apply theme cinnamon
# custom" của config.ini nhưng trước đây chưa có trong set này, khiến
# validate_every_entry() ném HclError và làm build --strict fail.
FUNCTION_NAMES = {
    "fileinstall", "filecustom", "filetheme", "filecopy", "command", "make", "call",
}

SIZE_RE = re.compile(
    r"^(?P<off>false)$"
    r"|^(?P<num>\d+(?:\.\d+)?)(?P<unit>GB|MB)$"
    r"|^custom\s*>\s*(?P<cnum>\d+(?:\.\d+)?)(?P<cunit>GB|MB)$",
    re.IGNORECASE,
)
VERSION_RE = re.compile(r"^\d+(\.\d+){1,3}$")
FUNC_CALL_RE = re.compile(r"^(\w+)\((.*)\)$", re.DOTALL)


class HclError(Exception):
    """Lỗi cứng khi parse/resolve — dừng ngay, không đoán mò."""


@dataclass
class Diagnostic:
    level: str  # "error" | "warning"
    message: str


@dataclass
class ParsedValue:
    type: str
    raw: str
    value: object


# ---------------------------------------------------------------------------
# 2. LEXER / SECTION READER
# ---------------------------------------------------------------------------

def _strip_inline_comment(val: str) -> str:
    in_quotes = False
    for idx, ch in enumerate(val):
        if ch == '"':
            in_quotes = not in_quotes
        elif ch == ";" and not in_quotes:
            return val[:idx].strip()
    return val.strip()


@dataclass
class RawSection:
    name: str
    entries: list = field(default_factory=list)  # list[(key, raw_value, group)]


def read_sections(path: str) -> list:
    with open(path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    sections: list[RawSection] = []
    current: RawSection | None = None
    current_group = None

    def _is_delim(s: str) -> bool:
        return bool(re.fullmatch(r";={5,}", s.strip()))

    i = 0
    n = len(lines)
    while i < n:
        raw_line = lines[i].rstrip("\n")
        stripped = raw_line.strip()

        if (
            _is_delim(stripped)
            and i + 2 < n
            and lines[i + 1].strip().startswith(";")
            and not _is_delim(lines[i + 1])
            and _is_delim(lines[i + 2])
        ):
            label = lines[i + 1].strip()[1:].strip()
            if label and not label.upper().startswith("END"):
                current_group = label
            i += 3
            continue

        if stripped.startswith(";"):
            i += 1
            continue

        if not stripped:
            i += 1
            continue

        m = re.fullmatch(r"\[(.+)\]", stripped)
        if m:
            current = RawSection(name=m.group(1))
            sections.append(current)
            current_group = None
            i += 1
            continue

        if "=" in stripped:
            key, _, val = stripped.partition("=")
            key = key.strip()
            val = _strip_inline_comment(val.strip())

            if val.count("(") > val.count(")"):
                buf = [val]
                depth = val.count("(") - val.count(")")
                i += 1
                while i < n and depth > 0:
                    buf.append(lines[i].rstrip("\n"))
                    depth += lines[i].count("(") - lines[i].count(")")
                    i += 1
                val = "\n".join(buf)
            else:
                i += 1

            if current is None:
                raise HclError(
                    f"Dòng {i}: key '{key}' nằm ngoài mọi section — HCL yêu cầu "
                    f"mọi key phải thuộc 1 [section]."
                )
            current.entries.append((key, val, current_group))
            continue

        i += 1

    return sections


# ---------------------------------------------------------------------------
# 3. TYPE CLASSIFIER
# ---------------------------------------------------------------------------

def classify(key: str, raw: str) -> ParsedValue:
    raw = raw.strip()

    if key in SIZE_KEYS:
        norm = re.sub(r"custom\s*>\s*", "custom > ", raw.strip())
        m = SIZE_RE.match(norm)
        if not m:
            raise HclError(f"'{key} = {raw}' không khớp grammar SIZE (false | <n>GB|MB | custom > <n>GB|MB)")
        if m.group("off"):
            return ParsedValue("SIZE", raw, {"mode": "off", "mb": 0})
        if m.group("num"):
            n = float(m.group("num"))
            unit = m.group("unit").upper()
            mb = n * 1024 if unit == "GB" else n
            return ParsedValue("SIZE", raw, {"mode": "fixed", "mb": mb})
        n = float(m.group("cnum"))
        unit = m.group("cunit").upper()
        mb = n * 1024 if unit == "GB" else n
        return ParsedValue("SIZE", raw, {"mode": "custom", "mb": mb})

    if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
        return ParsedValue("STRING", raw, raw[1:-1])

    if raw.lower() in ("true", "false"):
        return ParsedValue("BOOLEAN", raw, raw.lower() == "true")

    if raw.startswith("${") and raw.endswith("}"):
        return ParsedValue("REFERENCE", raw, raw[2:-1])

    fm = FUNC_CALL_RE.match(raw)
    if fm:
        fname, fargs = fm.group(1), fm.group(2).strip()
        if fname not in FUNCTION_NAMES:
            raise HclError(
                f"Function '{fname}(...)' không nằm trong FUNCTION set hợp lệ "
                f"của HCL 1.0: {sorted(FUNCTION_NAMES)}"
            )
        if "\n" in fargs or "=" in fargs and fname == "command":
            kwargs = {}
            for line in fargs.splitlines():
                line = line.strip().rstrip(",")
                if not line or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                kwargs[k.strip()] = classify(k.strip(), v.strip())
            return ParsedValue("FUNCTION", raw, {"name": fname, "kwargs": {
                k: v.value for k, v in kwargs.items()
            }})
        else:
            arg = fargs.strip()
            return ParsedValue("FUNCTION", raw, {"name": fname, "arg": arg})

    if VERSION_RE.match(raw):
        return ParsedValue("VERSION", raw, raw)

    if re.fullmatch(r"-?\d+(\.\d+)?", raw):
        return ParsedValue("NUMBER", raw, float(raw) if "." in raw else int(raw))

    if re.fullmatch(r"[A-Za-z_][\w\-]*", raw):
        return ParsedValue("REFERENCE_OR_ENUM", raw, raw)

    return ParsedValue("STRING", raw, raw)


# ---------------------------------------------------------------------------
# 4. RESOLVER
# ---------------------------------------------------------------------------

class Resolver:
    def __init__(self, sections: list, root: str):
        self.sections = {s.name: s for s in sections}
        self.order = [s.name for s in sections]
        self.root = root
        self.diags: list[Diagnostic] = []

    def _entries(self, section_name: str):
        sec = self.sections.get(section_name)
        if sec is None:
            return []
        return sec.entries

    def _kv(self, section_name: str) -> dict:
        return {k: v for k, v, _ in self._entries(section_name)}

    def resolve_enum_section(self, section_name: str) -> str | None:
        kv = self._kv(section_name)
        true_keys = []
        for k, raw in kv.items():
            pv = classify(k, raw)
            if pv.type == "BOOLEAN" and pv.value is True:
                true_keys.append(k)
        if len(true_keys) == 0:
            self.diags.append(Diagnostic(
                "error", f"[{section_name}] không có key nào = true (cần đúng 1)."))
            return None
        if len(true_keys) > 1:
            self.diags.append(Diagnostic(
                "error",
                f"[{section_name}] có {len(true_keys)} key = true cùng lúc "
                f"({', '.join(true_keys)}) — section này phải là ENUM (chỉ 1 true)."))
        return true_keys[0]

    def resolve_reference_value(self, ref_name: str):
        if ref_name in self.sections:
            kv = self._kv(ref_name)
            all_bool = all(
                classify(k, v).type == "BOOLEAN" for k, v in kv.items()
            ) and len(kv) > 0
            if all_bool:
                return self.resolve_enum_section(ref_name)
            return {k: self.resolve_value(k, v) for k, v in kv.items()}

        for sec_name in self.order:
            kv = self._kv(sec_name)
            if ref_name in kv:
                return self.resolve_value(ref_name, kv[ref_name])

        self.diags.append(Diagnostic(
            "error", f"Không resolve được reference '{ref_name}' — không có "
                     f"section hay key nào tên đó."))
        return None

    def resolve_value(self, key: str, raw: str):
        pv = classify(key, raw)
        if pv.type == "REFERENCE":
            return self.resolve_reference_value(pv.value)
        if pv.type == "REFERENCE_OR_ENUM":
            if pv.value in self.sections:
                return self.resolve_reference_value(pv.value)
            return pv.value
        if pv.type == "FUNCTION":
            return self.resolve_function(pv.value)
        if pv.type == "SIZE":
            return pv.value
        return pv.value

    def resolve_function(self, fn: dict):
        name = fn["name"]
        if "arg" in fn:
            arg = fn["arg"]
            result = {"call": name, "path": arg}
            # PATCH: thêm filetheme/filecopy vào nhóm hàm có path cần
            # existence-check, giống fileinstall/filecustom/make.
            if name in ("fileinstall", "filecustom", "filetheme", "filecopy", "make") and arg:
                if arg.startswith("http://") or arg.startswith("https://"):
                    result["is_url"] = True
                    result["url"] = arg
                else:
                    result["is_url"] = False
                    full = os.path.normpath(os.path.join(self.root, arg))
                    if not os.path.exists(full):
                        self.diags.append(Diagnostic(
                            "error", f"{name}({arg}) — file/thư mục không tồn tại: {full}"))
                    result["exists"] = os.path.exists(full)
            return result
        kwargs = fn["kwargs"]
        result = {"call": name, **kwargs}
        if name == "command" and "file" in kwargs:
            full = os.path.normpath(os.path.join(self.root, str(kwargs["file"])))
            if not os.path.exists(full):
                self.diags.append(Diagnostic(
                    "error", f"command(file={kwargs['file']}) — script không tồn tại: {full}"))
        return result

    def resolve_my_version_os_base(self) -> dict:
        kv = self._kv("my-version-os-base")
        out = {}
        out["version"] = self.resolve_value("Version", kv["Version"])
        out["codename"] = self.resolve_value("codename", kv["codename"])

        base_choice = self.resolve_enum_section("Base")
        out["base"] = base_choice

        kernel_raw = classify("kernel", kv["kernel"]).value
        kernel_section = f"kernel.{kernel_raw}"
        if kernel_section not in self.sections:
            self.diags.append(Diagnostic(
                "error",
                f"kernel = \"{kernel_raw}\" nhưng không tìm thấy section "
                f"[{kernel_section}]."))
            out["kernel_profile"] = None
        else:
            profile = {k: self.resolve_value(k, v) for k, v in self._kv(kernel_section).items()}
            out["kernel_profile_name"] = kernel_raw
            out["kernel_profile"] = profile
            de = profile.get("desktop")
            if de:
                de_kv = self._kv("Desktop-Environment")
                match = next((k for k in de_kv if k.lower() == str(de).lower()), None)
                if match is None:
                    self.diags.append(Diagnostic(
                        "warning",
                        f"[kernel.{kernel_raw}] desktop = {de} nhưng không có key "
                        f"tương ứng trong [Desktop-Environment]."))
                elif classify(match, de_kv[match]).value is not True:
                    self.diags.append(Diagnostic(
                        "warning",
                        f"[kernel.{kernel_raw}] chọn desktop = {de}, nhưng "
                        f"[Desktop-Environment] {match} = false. Hai nơi đang lệch nhau."))

        firmware_raw = classify("firmware", kv["firmware"]).value
        firmware_flag = self.resolve_reference_value(firmware_raw) \
            if firmware_raw not in self._kv("firmware") else \
            self.resolve_value(firmware_raw, self._kv("firmware")[firmware_raw])
        out["firmware_flag_name"] = firmware_raw
        out["firmware_enabled"] = firmware_flag
        fw_section_guess = f"firmware-{base_choice}" if base_choice else None
        if fw_section_guess and fw_section_guess not in self.sections:
            fw_section_guess = next(
                (s for s in self.order if s.lower() == f"firmware-{base_choice}".lower()),
                None,
            )
        out["firmware_section"] = fw_section_guess
        if fw_section_guess:
            pkgs = {
                k: self.resolve_value(k, v)
                for k, v in self._kv(fw_section_guess).items()
            }
            out["firmware_packages"] = {
                k: v for k, v in pkgs.items() if v is True
            }
        else:
            self.diags.append(Diagnostic(
                "warning",
                f"base = {base_choice} nhưng không có section firmware tương "
                f"ứng ([firmware-{base_choice}])."))
            out["firmware_packages"] = {}

        out["swap"] = self.resolve_value("swap", kv["swap"])
        out["config"] = self.resolve_value("config", kv["config"])

        name_tpl = classify("name", kv["name"]).value
        name = name_tpl
        name = name.replace("${Version}", str(out["version"]))
        name = name.replace("${codename}", str(out["codename"]))
        name = name.replace("${Base}", str(base_choice))
        out["name"] = name
        return out

    def resolve_package_groups(self) -> dict:
        groups: dict[str, dict] = {}
        for key, raw, group in self._entries("package"):
            g = group or "(ungrouped)"
            groups.setdefault(g, {})[key] = self.resolve_value(key, raw)
        return groups

    def resolve_easter_egg(self) -> dict:
        kv = self._kv_scan("make-Easter-Egg", "make-Easter-Egg-url")
        return {k: self.resolve_value(k, v) for k, v in kv.items()}

    def _kv_scan(self, *keys):
        found = {}
        for sec_name in self.order:
            kv = self._kv(sec_name)
            for k in keys:
                if k in kv and k not in found:
                    found[k] = kv[k]
        return found

    def validate_every_entry(self):
        for sec_name in self.order:
            for key, raw, _group in self._entries(sec_name):
                try:
                    classify(key, raw)
                except HclError as e:
                    self.diags.append(Diagnostic(
                        "error", f"[{sec_name}] {key} = {raw!r} — {e}"))

    def resolve_all(self) -> dict:
        result = {}
        result["base_profile"] = self.resolve_my_version_os_base()
        result["package_groups"] = self.resolve_package_groups()
        if "customization" in self.sections:
            result["customization"] = {
                k: self.resolve_value(k, v) for k, v, _ in self._entries("customization")
            }
        result["easter_egg"] = self.resolve_easter_egg()
        welcome_kv = self._kv_scan("linkhyggshi-welcome")
        result["welcome"] = {
            k: self.resolve_value(k, v) for k, v in welcome_kv.items()
        }
        return result


# ---------------------------------------------------------------------------
# 5. GITHUB ACTIONS ENV EXPORT
# ---------------------------------------------------------------------------

def to_env_lines(resolved: dict) -> list:
    bp = resolved["base_profile"]
    lines = []

    def put(k, v):
        v = "" if v is None else v
        lines.append(f"HCL_{k}={v}")

    put("HYGGSHI_NAME", bp.get("name"))
    put("HYGGSHI_VERSION", bp.get("version"))
    put("HYGGSHI_CODENAME", bp.get("codename"))
    put("BASE_DISTRO", str(bp.get("base") or "").lower())
    put("DESKTOP_PROFILE", bp.get("kernel_profile_name"))
    kp = bp.get("kernel_profile") or {}
    put("DESKTOP_ENV", kp.get("desktop"))

    swap = bp.get("swap") or {}
    put("SWAP_MODE", swap.get("mode"))
    put("SWAP_MB", int(swap.get("mb", 0)))

    fw_pkgs = bp.get("firmware_packages") or {}
    put("FIRMWARE_ENABLED", str(bool(bp.get("firmware_enabled"))).lower())
    put("FIRMWARE_PACKAGES", " ".join(sorted(fw_pkgs.keys())))

    pkg_groups = resolved.get("package_groups", {})
    de = (kp.get("desktop") or "").lower()
    de_group_names = {"xfce", "cinnamon", "kde", "kde plasma", "lxqt", "gnome", "mate", "cli"}

    app_installs = []
    app_urls = []
    all_packages = []
    desktop_packages = []
    desktop_group = ""

    for g_name, g_pkgs in pkg_groups.items():
        g_lower = g_name.lower().strip()
        is_de_group = any(de_name in g_lower for de_name in de_group_names)
        is_active_de = (de in g_lower) or (g_lower in de) if is_de_group else False

        if is_active_de:
            desktop_group = g_name

        for k, v in g_pkgs.items():
            if isinstance(v, dict) and v.get("call") == "fileinstall":
                p = v.get("path", "")
                if p:
                    app_installs.append(p)
                    if v.get("is_url"):
                        app_urls.append(p)
            elif v is True:
                if is_de_group:
                    if is_active_de:
                        desktop_packages.append(k)
                        all_packages.append(k)
                else:
                    all_packages.append(k)

    put("APP_INSTALLS", " ".join(app_installs))
    put("APP_URLS", " ".join(app_urls))
    put("DESKTOP_PACKAGES", " ".join(desktop_packages))
    put("DESKTOP_PACKAGE_GROUP", desktop_group)
    put("ALL_PACKAGES", " ".join(all_packages))

    ee = resolved.get("easter_egg", {})
    put("EASTER_EGG_ENABLED", str(bool(ee.get("make-Easter-Egg"))).lower())
    ee_url = ee.get("make-Easter-Egg-url") or {}
    put("EASTER_EGG_PATH", ee_url.get("path", ""))

    welcome = resolved.get("welcome", {}).get("linkhyggshi-welcome", {})
    put("WELCOME_SCRIPT", welcome.get("file", ""))
    put("WELCOME_ACTION", welcome.get("action", ""))

    base_val     = str(bp.get("base") or "").lower()
    kp_val       = bp.get("kernel_profile") or {}
    de_val       = str(kp_val.get("desktop") or "").lower()
    name_val     = bp.get("name")
    version_val  = bp.get("version")
    codename_val = bp.get("codename")

    if base_val:
        lines.append(f"BASE_DISTRO={base_val}")
    if de_val:
        lines.append(f"DE={de_val}")
    if name_val:
        lines.append(f"DISTRO_NAME={name_val}")
    if version_val:
        lines.append(f"HYGGSHI_VERSION_ID={version_val}")
    if codename_val:
        lines.append(f"HYGGSHI_CODENAME={codename_val}")
    if app_installs:
        lines.append(f"HCL_APP_INSTALLS={' '.join(app_installs)}")
    if app_urls:
        lines.append(f"HCL_APP_URLS={' '.join(app_urls)}")
    if all_packages:
        lines.append(f"HCL_PACKAGES={' '.join(all_packages)}")

    return lines


# ---------------------------------------------------------------------------
# 6. CLI
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="HCL 1.0 parser/resolver cho Hyggshi OS config.ini")
    ap.add_argument("config", help="đường dẫn tới config.ini")
    ap.add_argument("--root", default=".", help="root repo để resolve đường dẫn file")
    ap.add_argument("--emit-json", help="ghi kết quả resolve ra file JSON")
    ap.add_argument("--emit-env", help="ghi biến môi trường (KEY=VALUE) ra file")
    ap.add_argument("--strict", action="store_true", help="exit(1) nếu có bất kỳ error nào sau validate")
    args = ap.parse_args()

    try:
        sections = read_sections(args.config)
    except HclError as e:
        print(f"::error::[HCL parse] {e}", file=sys.stderr)
        sys.exit(1)

    resolver = Resolver(sections, root=args.root)
    resolver.validate_every_entry()

    try:
        resolved = resolver.resolve_all()
    except HclError as e:
        print(f"::error::[HCL resolve] {e}", file=sys.stderr)
        sys.exit(1)

    errors = [d for d in resolver.diags if d.level == "error"]
    warnings = [d for d in resolver.diags if d.level == "warning"]

    for w in warnings:
        print(f"::warning::[HCL] {w.message}")
    for e in errors:
        print(f"::error::[HCL] {e.message}", file=sys.stderr)

    if args.emit_json:
        with open(args.emit_json, "w", encoding="utf-8") as f:
            json.dump(resolved, f, ensure_ascii=False, indent=2, default=str)
        print(f"[HCL] đã ghi {args.emit_json}")

    if args.emit_env:
        lines = to_env_lines(resolved)
        with open(args.emit_env, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        print(f"[HCL] đã append {len(lines)} biến env vào {args.emit_env}")

    print(f"[HCL] Base = {resolved['base_profile'].get('base')}, "
          f"Desktop = {(resolved['base_profile'].get('kernel_profile') or {}).get('desktop')}, "
          f"Swap = {resolved['base_profile'].get('swap')}")

    if errors and args.strict:
        print(f"::error::[HCL] {len(errors)} lỗi validate, dừng build (--strict).", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
