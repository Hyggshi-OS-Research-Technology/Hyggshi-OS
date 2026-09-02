#!/usr/bin/env python3
"""
hcl_parser.py — Parser + Resolver + Validator cho Hyggshi Configuration
Language (HCL) v1.0.

File .ini của Hyggshi OS (iso-config/config/config.ini) không phải INI
thuần: nó có reference resolution (${Base}), key-driven dispatch
(kernel = "Desktop" -> [kernel.Desktop]), typed literals (SIZE: 1GB /
custom > 7.2GB), và function calls (fileinstall(), filecustom(),
filetheme(), filecopy(), fileaddtext(), command(...), make(),
installkernel(...)). Script này parse toàn bộ thành AST, resolve hết
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
#
# PATCH 2: thêm fileaddtext — dùng trong [package-debian-test.full/normal/
# default/unstable] (add-repository1/2/3 = fileaddtext(target=... content=...))
# để ghi dòng "deb ..." vào /etc/apt/sources.list. Cùng bug y hệt filetheme/
# filecopy trước đó: function mới xuất hiện trong config.ini nhưng chưa được
# đăng ký -> validate_every_entry() báo lỗi cho toàn bộ 4 profile repo.
#
# PATCH 3: thêm installkernel — dùng trong [package] ở khối "kernel install
# and compilers (coming soon...)" (kernel-install = installkernel(target=...
# kernel-version=... compilers=...)). Hiện khối này đang comment (";") trong
# config.ini nên chưa active, nhưng cú pháp installkernel(...) đã xuất hiện
# sẵn trong file -> đăng ký trước ở đây để lúc bỏ comment kích hoạt,
# validate_every_entry() không báo "Function 'installkernel(...)' không nằm
# trong FUNCTION set hợp lệ" (cùng loại bug đã gặp với filetheme/filecopy/
# fileaddtext).
FUNCTION_NAMES = {
    "fileinstall", "filecustom", "filetheme", "filecopy", "fileaddtext",
    "command", "make", "call", "installkernel",
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
            # PATCH: filetheme trỏ path NGUỒN trong repo -> check tồn tại.
            # filecopy trỏ path ĐÍCH trên rootfs ISO lúc build/cài đặt (vd
            # /usr/share/themes/...) -> KHÔNG tồn tại trong repo lúc build,
            # đó là bản chất của nó (đích sinh ra sau, không phải trước).
            # Bug thật: gộp chung nhóm khiến build --strict fail oan ở CI
            # (xem log: "filecopy(...) — file/thư mục không tồn tại").
            if name in ("fileinstall", "filecustom", "filetheme", "make") and arg:
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
        if name == "installkernel":
            # installkernel(target=..., kernel-version=..., compilers=...)
            # "target" ở đây không phải path trong repo (khác fileinstall/
            # filecustom/filetheme) mà là đường dẫn HỆ THỐNG sẽ ghi/patch lúc
            # build (vd apt source list) hoặc đơn thuần placeholder chưa dùng
            # tới — nên KHÔNG check tồn tại trên đĩa ở đây, giống lý do
            # filecopy() không check (xem PATCH ở resolve_function phía trên
            # cho "arg" case). Việc thật sự cần validate là có khai
            # kernel-version hay chưa, vì đó là input bắt buộc để build.sh
            # biết compile/cài kernel nào.
            if not kwargs.get("kernel-version"):
                self.diags.append(Diagnostic(
                    "error",
                    "installkernel(...) thiếu 'kernel-version' — bắt buộc để "
                    "biết build/cài kernel version nào."))
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

    def resolve_apt_repository(self) -> dict | None:
        """
        PATCH: dispatch package-debian-test = <profile> (full/normal/default/
        unstable) -> [package-debian-test.<profile>], giống cách kernel =
        "Desktop" -> [kernel.Desktop] đã có sẵn ở resolve_my_version_os_base().

        Bug trước đó: resolve_package_groups() chỉ quét entries nằm trực
        tiếp trong section [package], nên key "package-debian-test = full"
        chỉ được đọc ra CHUỖI "full" chứ không hề mở section
        [package-debian-test.full] tương ứng — add-repository1/2/3
        (fileaddtext) bị bỏ qua hoàn toàn dù build.sh cần nội dung đó để
        ghi /etc/apt/sources.list.
        """
        kv = self._kv("package")
        if "package-debian-test" not in kv:
            return None

        profile = self.resolve_value("package-debian-test", kv["package-debian-test"])
        section_name = f"package-debian-test.{profile}"
        if section_name not in self.sections:
            self.diags.append(Diagnostic(
                "error",
                f"package-debian-test = {profile!r} nhưng không tìm thấy "
                f"section [{section_name}]."))
            return {"profile": profile, "target_file": None, "repositories": []}

        entries = {
            k: self.resolve_value(k, v) for k, v, _ in self._entries(section_name)
        }
        target_file = entries.pop("apt-target-file", None)

        repos = []
        for key in sorted(k for k in entries if k.startswith("add-repository")):
            val = entries[key]
            if isinstance(val, dict) and val.get("call") == "fileaddtext":
                repos.append({
                    "key": key,
                    "target": val.get("target", target_file),
                    "content": val.get("content"),
                })
            else:
                self.diags.append(Diagnostic(
                    "warning",
                    f"[{section_name}] {key} không phải fileaddtext(...) — bỏ qua."))

        return {
            "profile": profile,
            "target_file": target_file,
            "repositories": repos,
        }

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
        result["apt_repository"] = self.resolve_apt_repository()
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

def to_env_lines(resolved: dict, de_override: str | None = None) -> list:
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

    # BUG: [kernel.<Edition>].desktop trong config.ini là giá trị TĨNH (vd
    # "Cinnamon" theo default hiện tại của kernel.Desktop), hoàn toàn tách
    # rời khỏi lựa chọn DE THỰC SỰ mà người dùng chọn ở workflow_dispatch
    # input "desktop" (env.DE, vd "xfce"). desktop.sh cài đúng DE theo $DE
    # (switch-case), nhưng khối dưới đây trước đó vẫn lọc package_groups
    # theo kp.get("desktop") tĩnh — nên khi build XFCE (DE=xfce) mà
    # config.ini còn khai desktop=Cinnamon, TOÀN BỘ gói cinnamon/cinnamon-*
    # trong nhóm ";Cinnamon" vẫn bị coi là "active DE group", lọt vào
    # HCL_PACKAGES -> EXTRA_PACKAGES -> apt-get install trong desktop.sh,
    # cài chồng Cinnamon lên cạnh XFCE dù người dùng không hề chọn Cinnamon.
    #
    # Fix: nhận de_override (giá trị $DE thật từ workflow input, xem
    # main()/CLI --de-override) và dùng nó làm nguồn sự thật DUY NHẤT để
    # lọc package_groups khi có mặt — kể cả khi nó khác với
    # [kernel.<Edition>].desktop trong config.ini. Không override thì giữ
    # nguyên hành vi cũ (dùng kp.get("desktop")) để không phá các lần gọi
    # hcl_parser.py không truyền --de-override (vd chạy tay để debug).
    de_effective = (de_override or kp.get("desktop") or "")
    put("DESKTOP_ENV", de_effective)
    if de_override and de_override.strip().lower() != str(kp.get("desktop") or "").strip().lower():
        print(
            f"[HCL] --de-override='{de_override}' khác với "
            f"[kernel.{bp.get('kernel_profile_name')}].desktop='{kp.get('desktop')}' "
            f"trong config.ini — dùng '{de_override}' làm DE thật để lọc gói "
            f"(mọi package liên quan tới DE khác, kể cả Cinnamon, sẽ bị loại khỏi HCL_PACKAGES)."
        )

    swap = bp.get("swap") or {}
    put("SWAP_MODE", swap.get("mode"))
    put("SWAP_MB", int(swap.get("mb", 0)))

    fw_pkgs = bp.get("firmware_packages") or {}
    put("FIRMWARE_ENABLED", str(bool(bp.get("firmware_enabled"))).lower())
    put("FIRMWARE_PACKAGES", " ".join(sorted(fw_pkgs.keys())))

    # [config-setup-postpartum-care] (out["config"], resolved qua tham chiếu
    # ${config-setup-postpartum-care} trong [my-version-os-base]) — trước đây
    # dict này được resolve nhưng CHƯA BAO GIỜ export ra env, nên squashfs-
    # max-compression (và Time-zone/lang/stylexfce) chỉ nằm chết trong
    # /tmp/hcl-resolved.json, iso.sh/desktop.sh không đọc được. Export đúng
    # squashfs-max-compression ở đây để scripts/iso.sh dùng.
    cfg = bp.get("config") or {}
    put("SQUASHFS_MAX_COMPRESSION", str(bool(cfg.get("squashfs-max-compression"))).lower())

    pkg_groups = resolved.get("package_groups", {})
    de = de_effective.lower()
    # BUG ĐÃ SỬA: trước đây match bằng substring ("cinnamon" in g_lower),
    # nên nhóm KHÔNG PHẢI package-per-DE nhưng có chữ "cinnamon" trong tên
    # comment header — vd "; apply theme cinnamon custom" phía trên khối
    # XFCE/Cinnamon/... — cũng bị coi là group DE Cinnamon, kéo theo
    # theme-light-enabled/theme-dark-enabled (là BOOLEAN cấu hình, không
    # phải tên gói apt) lọt vào apt-get install cùng các gói cinnamon-*
    # thật. Đổi sang so khớp CHÍNH XÁC (exact match, sau khi chuẩn hoá)
    # với đúng 7 tên group DE thật trong config.ini — không còn match mờ.
    DE_GROUP_EXACT = {
        "xfce": "xfce",
        "cinnamon": "cinnamon",
        "kde plasma": "kde",
        "lxqt": "lxqt",
        "gnome": "gnome",
        "mate": "mate",
        "cli": "cli",
    }

    app_installs = []
    app_urls = []
    all_packages = []
    desktop_packages = []
    desktop_group = ""
    kernel_install = None  # PATCH 3: installkernel(...) — xem FUNCTION_NAMES

    for g_name, g_pkgs in pkg_groups.items():
        g_lower = g_name.lower().strip()
        de_id = DE_GROUP_EXACT.get(g_lower)
        is_de_group = de_id is not None
        is_active_de = is_de_group and (de == de_id or de.replace(" ", "") == de_id.replace(" ", ""))

        if is_active_de:
            desktop_group = g_name

        for k, v in g_pkgs.items():
            if isinstance(v, dict) and v.get("call") == "fileinstall":
                p = v.get("path", "")
                if p:
                    app_installs.append(p)
                    if v.get("is_url"):
                        app_urls.append(p)
            elif isinstance(v, dict) and v.get("call") == "installkernel":
                # Chỉ nên có 1 khai báo installkernel(...) trong config.ini;
                # nếu có nhiều, lấy cái gặp đầu tiên và cảnh báo (giống cách
                # [Base]/[Desktop-Environment] enforce ENUM — nhưng ở đây
                # không phải lỗi cứng vì không có gì trong grammar cấm khai
                # 2 lần, chỉ là không rõ cái nào build.sh nên dùng).
                if kernel_install is None:
                    kernel_install = v
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

    put("KERNEL_INSTALL_ENABLED", str(kernel_install is not None).lower())
    if kernel_install is not None:
        put("KERNEL_INSTALL_VERSION", kernel_install.get("kernel-version", ""))
        put("KERNEL_INSTALL_TARGET", kernel_install.get("target", ""))
        put("KERNEL_INSTALL_COMPILERS", str(bool(kernel_install.get("compilers"))).lower())

    apt = resolved.get("apt_repository")
    if apt:
        put("APT_PROFILE", apt.get("profile"))
        put("APT_TARGET_FILE", apt.get("target_file"))
        repos = apt.get("repositories") or []
        put("APT_REPO_COUNT", len(repos))
        for idx, r in enumerate(repos, start=1):
            put(f"APT_REPO_{idx}", r.get("content"))

    ee = resolved.get("easter_egg", {})
    put("EASTER_EGG_ENABLED", str(bool(ee.get("make-Easter-Egg"))).lower())
    ee_url = ee.get("make-Easter-Egg-url") or {}
    put("EASTER_EGG_PATH", ee_url.get("path", ""))

    welcome = resolved.get("welcome", {}).get("linkhyggshi-welcome", {})
    put("WELCOME_SCRIPT", welcome.get("file", ""))
    put("WELCOME_ACTION", welcome.get("action", ""))

    base_val     = str(bp.get("base") or "").lower()
    # BUG ĐÃ SỬA: dòng này trước đây tự đọc lại kp_val.get("desktop") (giá
    # trị TĨNH từ config.ini), bỏ qua de_override/de_effective đã tính ở
    # trên — nên dù --de-override đã lọc HCL_DESKTOP_PACKAGES đúng theo DE
    # người dùng chọn (vd xfce), dòng "DE=..." KHÔNG PREFIX xuất ra ở đây
    # vẫn ghi "DE=cinnamon" (theo config.ini) vào $GITHUB_ENV — vì GitHub
    # Actions dùng giá trị SET SAU CÙNG cho 1 biến env cùng tên trong cùng
    # job, dòng này sẽ ÂM THẦM GHI ĐÈ lại DE=xfce mà chính workflow input
    # "desktop" đã set trước đó, khiến desktop.sh (đọc $DE để cài DE) và
    # step "[cinnamon-fix]" (if: env.DE == 'cinnamon') nhận nhầm DE thật.
    # Dùng đúng de_effective (đã ưu tiên de_override) để 3 nguồn — package
    # filtering, HCL_DESKTOP_ENV, và DE ghi ra đây — luôn khớp nhau.
    de_val       = de_effective.lower()
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
    ap.add_argument(
        "--de-override",
        default=None,
        help=(
            "Desktop environment THẬT được người dùng chọn (vd $DE từ workflow "
            "input 'desktop': xfce/cinnamon/kde/lxqt/gnome/mate/cli). Khi được "
            "truyền, giá trị này thay thế [kernel.<Edition>].desktop tĩnh trong "
            "config.ini làm nguồn lọc package_groups active — tránh gói của DE "
            "không được chọn (vd Cinnamon) lọt vào HCL_PACKAGES khi build DE khác (vd XFCE)."
        ),
    )
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
        lines = to_env_lines(resolved, de_override=args.de_override)
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
