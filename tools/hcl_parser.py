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
#
# PATCH 4: thêm apply — dùng trong [Desktop-Environment], khối "Apply image
# background" (vd `xfce4 = apply(target = "usr/share/backgrounds/hyggshi/
# Verdant-Valley.png" runcommand = "")`). Cùng bug y hệt 3 patch trước:
# function mới xuất hiện trong config.ini nhưng chưa đăng ký -> toàn bộ
# entry apply(...) bị validate_every_entry() báo lỗi cứng, build --strict
# fail dù bản thân config.ini không sai gì cả.
#
# PATCH 5: thêm flathubinstall — dùng trong [Call-gnome-apps]
# (`flathubinstall(org.gnome.Loupe)`, ...). Arg là Flatpak Application ID,
# KHÔNG phải path trong repo -> resolve_function() không check tồn tại cho
# tên function này (xem nhánh "arg" trong resolve_function). Lưu ý: các
# dòng gọi flathubinstall(...) trong config.ini KHÔNG có "key =" phía
# trước (khác mọi function khác trong file) -> xem PATCH bare-call trong
# read_sections(), nếu không có patch đó thì dù đăng ký tên function ở
# đây, các dòng này vẫn bị bỏ qua hoàn toàn ngay từ bước đọc file.
#
# PATCH 6: thêm appremove/fileremove — dùng trong khối "Remove package and
# image" của config.ini (vd `systemsettings-KDE = appremove(run = "sudo apt
# remove systemsettings")`, `image-background = fileremove(run = "sudo rm -r
# /usr/share/backgrounds/xfce")`). Cùng bug y hệt các function trước: chưa
# đăng ký -> validate_every_entry() báo lỗi cứng cho cả 2 dòng này. Cả hai
# đều chỉ cần 1 kwarg bắt buộc "run" (lệnh shell sẽ chạy lúc build/chroot),
# KHÔNG có path nào để check tồn tại (khác fileinstall/filecustom/filetheme)
# -> không thêm vào nhánh check-tồn-tại trong resolve_function(), giống lý
# do flathubinstall/apply/installkernel không check tồn tại ở trên.
#
# PATCH 9: thêm copy — dùng trong khối "Remove package and image" của
# config.ini, cụ thể `image-background = copy(source=... rename=...
# target=...)`. Khác filecopy(source=,target=) (PATCH 7 ở resolve_
# file_copies): copy() có thêm kwarg "rename" — đổi tên file lúc copy sang
# đích thay vì giữ nguyên basename của source. Đăng ký ở đây cùng lý do
# mọi function mới trước đó: chưa có trong FUNCTION_NAMES -> classify()
# ném HclError "không nằm trong FUNCTION set hợp lệ", validate_every_
# entry() fail cứng dù cú pháp trong config.ini không sai gì.
# PATCH 10: thêm installer — dùng trong [Call-gnome-apps] và các khối khác
# khi cần khai `<key> = installer(run = "apt install -y <pkg>")` (cài package
# thêm bên trong chroot, không thuộc danh sách gói BOOLEAN thông thường).
# Cùng cơ chế appremove/fileremove (PATCH 6): validate kwarg "run", gom vào
# resolve_installers(), export INSTALLER_{idx} env, desktop.sh đọc JSON và
# chạy lệnh trong chroot — KHÔNG tạo file .sh riêng, KHÔNG hardcode vào
# workflow YAML.
# PATCH 13: thêm add-extension-gnome / add-tweak-gnome — dùng trong
# [call-gnome-extensions] và [call-gnome-tweak] (các entry kỹ thuật
# giống installer() nhưng chỉ chạy khi DE=gnome). Không check tồn tại path
# ("run" là lệnh shell, không phải path file trong repo), validate duy nhất
# là có kwarg "run" — cùng cơ chế với installer()/appremove()/fileremove().
FUNCTION_NAMES = {
    "fileinstall", "filecustom", "filetheme", "filecopy", "fileaddtext",
    "command", "make", "call", "installkernel", "apply", "flathubinstall",
    "appremove", "fileremove", "copy", "installer",
    "add-extension-gnome", "add-tweak-gnome",
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
    # PATCH 5: đếm riêng theo tên function, reset mỗi khi mở section mới —
    # dùng để sinh key giả cho các dòng gọi function TRẦN (không có "key =",
    # vd flathubinstall(org.gnome.Loupe) trong [Call-gnome-apps]). Xem nhánh
    # bare-call phía dưới.
    bare_call_counts: dict = {}

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
            bare_call_counts = {}
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

        # PATCH 5: dòng gọi function TRẦN, không có "key =" phía trước —
        # vd `flathubinstall(org.gnome.Loupe)` trong [Call-gnome-apps].
        # BUG TRƯỚC ĐÓ: nhánh "=" in stripped ở trên không match (không có
        # dấu "="), nên các dòng này rơi thẳng xuống `i += 1` cuối vòng lặp
        # và bị bỏ qua HOÀN TOÀN — [Call-gnome-apps] luôn resolve ra rỗng dù
        # file có 8 dòng flathubinstall(...), lỗi giống hệt bug
        # resolve_package_groups() đã sửa ở PATCH package-debian-test, chỉ
        # khác là ở đây mất ngay từ bước đọc file (read_sections), không
        # phải ở bước resolve. Sinh key giả "<fname>_<n>" (n đếm riêng theo
        # từng fname, reset mỗi section) để mỗi lời gọi có 1 key duy nhất
        # trong entries — bản thân key không có ý nghĩa gì, chỉ để tương
        # thích với cấu trúc (key, val, group) mà mọi chỗ khác đang dùng.
        bm = re.match(r"^([A-Za-z_]\w*)\(", stripped)
        if bm:
            fname = bm.group(1)
            val = stripped
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
                    f"Dòng {i}: lệnh '{fname}(...)' nằm ngoài mọi section — "
                    f"HCL yêu cầu mọi entry phải thuộc 1 [section]."
                )
            bare_call_counts[fname] = bare_call_counts.get(fname, 0) + 1
            synthetic_key = f"{fname}_{bare_call_counts[fname]}"
            current.entries.append((synthetic_key, val, current_group))
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
        fname, fargs_raw = fm.group(1), fm.group(2)
        fargs = fargs_raw.strip()
        if fname not in FUNCTION_NAMES:
            raise HclError(
                f"Function '{fname}(...)' không nằm trong FUNCTION set hợp lệ "
                f"của HCL 1.0: {sorted(FUNCTION_NAMES)}"
            )
        # PATCH 7: BUG — điều kiện cũ `"\n" in fargs` kiểm tra trên fargs ĐÃ
        # .strip(), nên chỉ đúng khi function có ≥2 kwarg (mỗi kwarg 1 dòng
        # -> sau strip() đầu/cuối vẫn còn ít nhất 1 "\n" ở GIỮA 2 dòng, vd
        # fileaddtext(target=... \n content=...), command(file=... \n
        # action=...)). Với function chỉ có ĐÚNG 1 kwarg viết nhiều dòng —
        # đúng dạng appremove()/fileremove() trong config.ini:
        #     appremove(
        #         run = "sudo apt remove systemsettings"
        #     )
        # — fargs_raw TRƯỚC strip là "\n    run = \"...\"\n" (2 newline ở
        # ĐẦU và CUỐI, không có newline nào Ở GIỮA vì chỉ có 1 dòng nội
        # dung). .strip() xoá sạch 2 newline biên đó, để lại đúng 1 dòng
        # "run = \"...\"" KHÔNG CÒN "\n" nào -> rơi nhầm vào nhánh "arg"
        # (positional argument đơn) ở dưới, coi CẢ CHUỖI "run = \"sudo apt
        # remove systemsettings\"" là 1 path/arg duy nhất thay vì kwarg
        # "run" -> kwargs luôn rỗng -> "run" resolve ra "" (chuỗi rỗng) dù
        # config.ini không sai cú pháp gì — bug lộ ra đúng lúc thêm
        # appremove/fileremove (PATCH 6) vì đây là 2 function ĐẦU TIÊN chỉ
        # cần 1 kwarg duy nhất.
        #
        # Fix: kiểm tra newline trên fargs_raw (TRƯỚC strip) — phản ánh
        # đúng "function này được viết NHIỀU DÒNG trong file gốc hay
        # không", không phụ thuộc số lượng kwarg bên trong. Thêm fallback
        # regex `^[\w-]+\s*=`: nếu sau này ai viết gọn 1 dòng
        # (`run = "..."`) không xuống dòng, vẫn nhận diện đúng là kwargs
        # (không phải positional arg) — an toàn với mọi arg dạng path/URL/
        # app-id hiện có (fileinstall(./x), flathubinstall(org.gnome.Loupe),
        # make(https://...)) vì none trong số đó bắt đầu bằng
        # "<định_danh> =".
        is_kwargs_call = (
            "\n" in fargs_raw
            or bool(re.match(r"^[\w-]+\s*=", fargs))
            or ("=" in fargs and fname == "command")
        )
        if is_kwargs_call:
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
        # PATCH 8: config.ini có 2 section CÙNG TÊN "[package]" (1 cái ở
        # gần đầu chỉ chứa "package-debian-test = full", 1 cái ở dưới chứa
        # cmake/git/nexfetch/install-flatpak/...) — tác giả cố ý mở lại
        # "[package]" lần 2 chỉ để ĐÓNG section [package-debian-test.unstable]
        # lại (xem comment "ĐÓNG package-debian-test.unstable, MỞ LẠI
        # [package] ở đây" trong config.ini), với ý định 2 section cùng tên
        # sẽ được HIỂU LÀ MỘT.
        #
        # BUG: `{s.name: s for s in sections}` là dict comprehension — key
        # trùng thì giá trị SAU ghi đè giá trị TRƯỚC, không merge. Nên
        # self.sections["package"] chỉ còn trỏ tới section [package] THỨ
        # HAI, entries của section ĐẦU TIÊN ("package-debian-test = full")
        # biến mất hoàn toàn khỏi self._kv("package") — resolve_apt_repository()
        # luôn thấy "package-debian-test" not in kv -> trả về None, toàn bộ
        # tính năng chọn kênh apt (full/normal/default/unstable) im lặng
        # không hoạt động dù validate --strict pass sạch (không phải lỗi cú
        # pháp, chỉ là 1 section "biến mất" theo đúng ngữ nghĩa dict Python).
        #
        # Fix: merge entries của mọi section CÙNG TÊN theo đúng thứ tự xuất
        # hiện trong file (nối tiếp, không ghi đè) — khớp với ý định "coi 2
        # section cùng tên là một" mà tác giả comment đã nêu. self.order
        # chỉ giữ mỗi tên DUY NHẤT MỘT LẦN (lần xuất hiện đầu tiên) để các
        # hàm quét theo self.order (resolve_removals, resolve_flathub_apps,
        # resolve_desktop_apply, validate_every_entry...) không xử lý trùng
        # lặp cùng 1 section 2 lần.
        merged: dict[str, RawSection] = {}
        order: list[str] = []
        for s in sections:
            if s.name in merged:
                merged[s.name].entries.extend(s.entries)
            else:
                merged[s.name] = RawSection(name=s.name, entries=list(s.entries))
                order.append(s.name)
        self.sections = merged
        self.order = order
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
        is_de_sec = section_name.strip().lower() == "desktop-environment"
        for k, raw in kv.items():
            k_clean = k.strip().lower().replace("_", "-")
            if is_de_sec and k_clean in ("build-all-github-actions", "build-all-github-action", "build-all"):
                continue
            pv = classify(k, raw)
            if pv.type == "BOOLEAN" and pv.value is True:
                true_keys.append(k)
        if len(true_keys) == 0:
            if is_de_sec:
                # Nếu [Desktop-Environment] có Build-all-github-actions = true thì không cần 1 DE đơn lẻ nào = true
                for k, raw in kv.items():
                    if k.strip().lower().replace("_", "-") in ("build-all-github-actions", "build-all-github-action", "build-all"):
                        if classify(k, raw).value is True:
                            return None
            self.diags.append(Diagnostic(
                "error", f"[{section_name}] không có key nào = true (cần đúng 1)."))
            return None
        if len(true_keys) > 1:
            self.diags.append(Diagnostic(
                "error",
                f"[{section_name}] có {len(true_keys)} key = true cùng lúc "
                f"({', '.join(true_keys)}) — section này phải là ENUM (chỉ 1 true)."))
        return true_keys[0]

    def resolve_desktop_environment(self) -> dict:
        """
        PATCH 12: resolve [Desktop-Environment].
        Hỗ trợ cờ Build-all-github-actions (build nhiều DEs song song trên GitHub Actions matrix)
        và các DEs đơn lẻ (xfce, cinnamon, kde, lxqt, gnome, mate, cli).
        """
        sec = self._kv("Desktop-Environment") if "Desktop-Environment" in self.sections else {}
        out = {
            "build_all_github_actions": False,
            "active_desktop": None,
            "desktops_to_build": [],
        }
        known_desktops = ["xfce", "kde", "gnome", "cinnamon", "mate", "lxqt"]
        all_desktops_with_cli = known_desktops + ["cli"]

        # 1. Tìm cờ Build-all-github-actions
        for k, v in sec.items():
            k_clean = k.strip().lower().replace("_", "-")
            if k_clean in ("build-all-github-actions", "build-all-github-action", "build-all"):
                pv = classify(k, v)
                if pv.type == "BOOLEAN":
                    out["build_all_github_actions"] = bool(pv.value)

        # 2. Tìm các DE đang = true
        true_desktops = []
        for k, v in sec.items():
            k_lower = k.strip().lower()
            if k_lower in all_desktops_with_cli:
                pv = classify(k, v)
                if pv.type == "BOOLEAN" and pv.value is True:
                    true_desktops.append(k_lower)

        if out["build_all_github_actions"]:
            # Nếu bật build all: nếu có chọn >=1 DE thì build các DE được chọn,
            # nếu không chọn DE nào (tất cả false) thì build toàn bộ 6 DEs chính.
            out["desktops_to_build"] = true_desktops if true_desktops else known_desktops
            out["active_desktop"] = true_desktops[0] if true_desktops else "xfce"
        else:
            if len(true_desktops) == 1:
                out["active_desktop"] = true_desktops[0]
                out["desktops_to_build"] = [true_desktops[0]]
            elif len(true_desktops) == 0:
                # Không có DE nào true và không bật build-all
                out["active_desktop"] = None
                out["desktops_to_build"] = []
            else:
                out["active_desktop"] = true_desktops[0]
                out["desktops_to_build"] = true_desktops

        return out

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
            #
            # flathubinstall(...) cũng KHÔNG nằm trong nhóm check-tồn-tại:
            # arg của nó là Flatpak Application ID (vd "org.gnome.Loupe"),
            # không phải đường dẫn file/thư mục nào trong repo hay trên
            # rootfs, nên os.path.exists() không có ý nghĩa gì ở đây — nếu
            # lỡ thêm vào nhóm check, mọi dòng flathubinstall(...) sẽ luôn
            # báo lỗi "không tồn tại" oan uổng.
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
        if name == "command":
            if "file" in kwargs:
                full = os.path.normpath(os.path.join(self.root, str(kwargs["file"])))
                if not os.path.exists(full):
                    self.diags.append(Diagnostic(
                        "error", f"command(file={kwargs['file']}) — script không tồn tại: {full}"))
            elif not kwargs.get("run"):
                self.diags.append(Diagnostic(
                    "error", "command(...) cần có 'file' hoặc 'run'."))
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
        if name == "apply":
            # apply(target=..., runcommand=...) — "target" là đường dẫn ĐÍCH
            # trên rootfs lúc build (vd usr/share/backgrounds/hyggshi/
            # Verdant-Valley.png), KHÔNG phải path nguồn trong repo -> không
            # check tồn tại, cùng lý do với filecopy()/installkernel() ở
            # trên (đích sinh ra sau, không phải trước lúc build). Chỉ
            # "target" là bắt buộc; "runcommand" có thể để trống ("") nếu
            # chỉ cần ghi file tĩnh mà không cần chạy lệnh gì thêm.
            if not kwargs.get("target"):
                self.diags.append(Diagnostic(
                    "error",
                    "apply(...) thiếu 'target' — bắt buộc để biết ghi file "
                    "vào đâu trên rootfs."))
        if name == "filecopy" and "source" in kwargs:
            # filecopy(source=..., target=...) — khác filecopy(<path>) dạng
            # positional-arg ở nhánh "arg" phía trên (chỉ có 1 path = ĐÍCH
            # trên rootfs, không check tồn tại). Dạng kwargs này tự đủ cả
            # nguồn (source, path TRONG REPO, phải tồn tại lúc build — vd
            # "xfce4-desktop-config" trong khối "Apply image background")
            # và đích (target, trên rootfs, sinh ra sau -> không check,
            # cùng lý do target của apply()/filecopy(<path>) không check).
            src = str(kwargs.get("source", ""))
            full = os.path.normpath(os.path.join(self.root, src))
            if not os.path.exists(full):
                self.diags.append(Diagnostic(
                    "error",
                    f"filecopy(source={src}) — file/thư mục nguồn không tồn tại: {full}"))
            result["exists"] = os.path.exists(full)
            if not kwargs.get("target"):
                self.diags.append(Diagnostic(
                    "error",
                    "filecopy(source=..., ...) thiếu 'target' — bắt buộc để "
                    "biết copy nguồn vào đâu trên rootfs."))
        if name == "copy":
            # PATCH 9: copy(source=..., rename=..., target=...) — dùng trong
            # khối "Remove package and image" (vd `image-background =
            # copy(source="./iso-config/branding/desktop-grub.svg"
            # rename="xfce-x.svg" target="/usr/share/backgrounds/xfce/")`).
            # Giống filecopy(source=,target=) ở trên: source là path NGUỒN
            # trong repo (phải tồn tại lúc build) -> check tồn tại; target
            # là thư mục ĐÍCH trên rootfs (sinh ra sau lúc build) -> không
            # check tồn tại, cùng lý do target của filecopy()/apply() không
            # check. Khác filecopy(): có thêm "rename" (tên file mới lúc
            # copy sang đích, thay vì giữ nguyên basename của source) —
            # không bắt buộc; nếu bỏ trống thì basename gốc của source được
            # dùng làm tên tại đích. "resolved_target" ghép sẵn target +
            # tên file cuối cùng (rename nếu có, không thì basename(source))
            # để nơi gọi (resolve_file_copies/to_env_lines) không phải tự
            # ghép path lần nữa.
            src = str(kwargs.get("source", ""))
            full = os.path.normpath(os.path.join(self.root, src))
            if not os.path.exists(full):
                self.diags.append(Diagnostic(
                    "error",
                    f"copy(source={src}) — file/thư mục nguồn không tồn tại: {full}"))
            result["exists"] = os.path.exists(full)
            target = kwargs.get("target")
            if not target:
                self.diags.append(Diagnostic(
                    "error",
                    "copy(source=..., ...) thiếu 'target' — bắt buộc để biết "
                    "copy nguồn vào đâu trên rootfs."))
            rename = kwargs.get("rename")
            is_dir = os.path.isdir(full) if os.path.exists(full) else False
            result["is_dir"] = is_dir
            if is_dir:
                base_name = os.path.basename(src.rstrip("/"))
                tgt_clean = str(target).rstrip("/") if target else ""
                if rename:
                    result["resolved_target"] = os.path.join(str(target), str(rename)) if target else None
                elif tgt_clean.endswith("/" + base_name) or tgt_clean == base_name:
                    result["resolved_target"] = tgt_clean
                else:
                    result["resolved_target"] = (
                        os.path.join(str(target), base_name) if target else None
                    )
            else:
                final_name = rename if rename else os.path.basename(src)
                result["resolved_target"] = (
                    os.path.join(str(target), final_name) if target else None
                )
        if name in ("appremove", "fileremove"):
            # appremove(run=...) / fileremove(run=...) — "run" là lệnh shell
            # sẽ thực thi lúc build (gỡ package hoặc xoá file/thư mục), không
            # phải path trong repo hay trên rootfs -> không check tồn tại,
            # cùng lý do với installkernel()/apply() ở trên. Validate duy
            # nhất: phải có "run", nếu không thì entry này không làm gì cả.
            if not kwargs.get("run"):
                self.diags.append(Diagnostic(
                    "error",
                    f"{name}(...) thiếu 'run' — bắt buộc để biết lệnh gỡ/xoá "
                    f"nào sẽ chạy."))
        if name == "installer":
            # PATCH 10: installer(run=...) — "run" là lệnh shell cài package
            # (thường là "apt-get install -y <pkg>"), chạy trong chroot lúc
            # build. Không phải path -> không check tồn tại, giống appremove.
            # Validate duy nhất: phải có "run".
            if not kwargs.get("run"):
                self.diags.append(Diagnostic(
                    "error",
                    f"installer(...) thiếu 'run' — bắt buộc để biết lệnh "
                    f"cài nào sẽ chạy."))

        # PATCH 11: Hỗ trợ điều kiện Desktop Environment (DE) cho
        # appremove, fileremove, installer, command:
        # - exclude_de = "kde" / exclude_de = "kde, gnome"
        # - for_de = "xfce, gnome, cinnamon, lxqt"
        # - desktop = "..." (nếu bắt đầu bằng "!" như "!kde" -> exclude_de = "kde")
        # PATCH 13: mở rộng sang add-extension-gnome / add-tweak-gnome
        if name in ("appremove", "fileremove", "installer", "command",
                    "add-extension-gnome", "add-tweak-gnome"):
            exclude_de = kwargs.get("exclude_de") or kwargs.get("except_de") or kwargs.get("not_de")
            for_de = kwargs.get("for_de") or kwargs.get("only_de")
            desktop_kw = kwargs.get("desktop")
            if desktop_kw:
                d_str = str(desktop_kw).strip()
                if d_str.startswith("!"):
                    exclude_de = (str(exclude_de) + "," if exclude_de else "") + d_str[1:]
                else:
                    for_de = (str(for_de) + "," if for_de else "") + d_str
            if exclude_de:
                result["exclude_de"] = str(exclude_de).strip()
            if for_de:
                result["for_de"] = str(for_de).strip()

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
        gnome_apps_raw = kv.get("gnome-apps")
        if gnome_apps_raw is not None:
            out["gnome_apps"] = classify("gnome-apps", gnome_apps_raw).value
        else:
            out["gnome_apps"] = None

        # PATCH 13: đọc gnome-extensions và gnome-tweak từ [my-version-os-base]
        # — cùng pattern với gnome-apps: resolve_gnome_extensions()/
        # resolve_gnome_tweaks() sẽ kiểm tra giá trị này và active_de
        # trước khi chạy bất kỳ lệnh nào trong [call-gnome-extensions]/[call-gnome-tweak].
        gnome_ext_raw = kv.get("gnome-extensions")
        out["gnome_extensions"] = classify("gnome-extensions", gnome_ext_raw).value if gnome_ext_raw is not None else None

        gnome_tweak_raw = kv.get("gnome-tweak")
        out["gnome_tweak"] = classify("gnome-tweak", gnome_tweak_raw).value if gnome_tweak_raw is not None else None

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

    def resolve_desktop_apply(self) -> list:
        """
        PATCH 4: gom hết các entry `<key> = apply(target=..., runcommand=...)`
        rải rác trong config (hiện tại chỉ có trong [Desktop-Environment],
        khối "Apply image background" — vd `xfce4 = apply(...)`), quét toàn
        bộ section thay vì hardcode "Desktop-Environment" để hỗ trợ thêm
        apply() ở section khác sau này (vd apply theme/icon riêng cho từng
        DE). Mỗi entry giữ luôn section + key gốc (vd key "xfce4") để
        to_env_lines() biết entry nào ứng với DE đang active.
        """
        out = []
        for sec_name in self.order:
            for key, raw, _group in self._entries(sec_name):
                pv = classify(key, raw)
                if pv.type == "FUNCTION" and pv.value.get("name") == "apply":
                    resolved = self.resolve_function(pv.value)
                    out.append({
                        "section": sec_name,
                        "key": key,
                        "target": resolved.get("target"),
                        "runcommand": resolved.get("runcommand", ""),
                    })
        return out

    def resolve_flathub_apps(self, active_de: str | None = None) -> list:
        """
        PATCH 5: gom các lời gọi flathubinstall(<app-id>).
        Nếu section là [Call-gnome-apps], chỉ kích hoạt khi desktop environment
        đang active là GNOME (active_de == "gnome") và gnome-apps trong
        [my-version-os-base] không bị tắt (không phải False).
        """
        seen = set()
        out = []
        for sec_name in self.order:
            if sec_name.lower() == "call-gnome-apps":
                is_gnome = (active_de or "").strip().lower() == "gnome"
                gnome_apps_val = None
                if "my-version-os-base" in self.sections:
                    kv = self._kv("my-version-os-base")
                    if "gnome-apps" in kv:
                        gnome_apps_val = classify("gnome-apps", kv["gnome-apps"]).value
                if not is_gnome or gnome_apps_val is False:
                    continue
            for key, raw, _group in self._entries(sec_name):
                pv = classify(key, raw)
                if pv.type == "FUNCTION" and pv.value.get("name") == "flathubinstall":
                    app_id = pv.value.get("arg", "").strip()
                    if app_id and app_id not in seen:
                        seen.add(app_id)
                        out.append(app_id)
        return out

    def _is_gnome_section_active(
        self, sec_name_lower: str, flag_key: str, active_de: str | None
    ) -> bool:
        """
        PATCH 13: kiểm tra xem 1 section GNOME-only (call-gnome-extensions,
        call-gnome-tweak) có được phép chạy hay không:
          1. active_de phải là "gnome"
          2. khóa flag tương ứng trong [my-version-os-base] không phải False.
        sec_name_lower: tên section đã lower (vd "call-gnome-extensions").
        flag_key: tên key trong [my-version-os-base] (vd "gnome-extensions").
        """
        is_gnome = (active_de or "").strip().lower() == "gnome"
        if not is_gnome:
            return False
        flag_val = None
        if "my-version-os-base" in self.sections:
            kv = self._kv("my-version-os-base")
            if flag_key in kv:
                flag_val = classify(flag_key, kv[flag_key]).value
        return flag_val is not False

    def resolve_gnome_extensions(self, active_de: str | None = None) -> list:
        """
        PATCH 13: gom các entry add-extension-gnome(run=...) trong
        [call-gnome-extensions] — chỉ chạy khi DE=gnome.
        Mỗi entry lưu lại key + lệnh "run" để desktop.sh thực thi trong chroot.
        """
        out = []
        for sec_name in self.order:
            if sec_name.lower() == "call-gnome-extensions":
                if not self._is_gnome_section_active(
                    sec_name.lower(), "gnome-extensions", active_de
                ):
                    continue
            else:
                continue  # chỉ xuất từ đúng section này
            for key, raw, _group in self._entries(sec_name):
                pv = classify(key, raw)
                if pv.type == "FUNCTION" and pv.value.get("name") == "add-extension-gnome":
                    resolved = self.resolve_function(pv.value)
                    run_cmd = resolved.get("run")
                    if run_cmd:
                        out.append({"key": key, "run": run_cmd})
        return out

    def resolve_gnome_tweaks(self, active_de: str | None = None) -> list:
        """
        PATCH 13: gom các entry add-tweak-gnome(run=...) trong
        [call-gnome-tweak] — chỉ chạy khi DE=gnome.
        """
        out = []
        for sec_name in self.order:
            if sec_name.lower() == "call-gnome-tweak":
                if not self._is_gnome_section_active(
                    sec_name.lower(), "gnome-tweak", active_de
                ):
                    continue
            else:
                continue  # chỉ xuất từ đúng section này
            for key, raw, _group in self._entries(sec_name):
                pv = classify(key, raw)
                if pv.type == "FUNCTION" and pv.value.get("name") == "add-tweak-gnome":
                    resolved = self.resolve_function(pv.value)
                    run_cmd = resolved.get("run")
                    if run_cmd:
                        out.append({"key": key, "run": run_cmd})
        return out

    def _is_de_excluded(
        self,
        active_de: str | None,
        exclude_de: str | None,
        for_de: str | None,
        key: str = "",
        run_cmd: str = "",
    ) -> bool:
        """
        Kiểm tra xem 1 entry (appremove, fileremove, installer) có bị loại trừ
        theo DE đang active hay không.
        - Safety invariant: nếu active_de là 'kde', KHÔNG BAO GIỜ gỡ systemsettings
          (Control Center cốt lõi của KDE Plasma).
        - exclude_de: danh sách DE bị loại trừ (vd 'kde' hoặc 'kde, gnome').
        - for_de: danh sách DE được phép chạy (vd 'xfce, gnome, cinnamon, lxqt').
        """
        if not active_de:
            return False
        cur_de = active_de.strip().lower()

        # Bảo vệ an toàn tuyệt đối cho KDE Plasma:
        if cur_de == "kde":
            if key == "systemsettings-KDE" or (
                "systemsettings" in run_cmd and ("remove" in run_cmd or "purge" in run_cmd)
            ):
                return True

        if exclude_de:
            ex_list = [x.strip().lower() for x in str(exclude_de).split(",") if x.strip()]
            if cur_de in ex_list:
                return True

        if for_de:
            for_list = [x.strip().lower() for x in str(for_de).split(",") if x.strip()]
            if cur_de not in for_list:
                return True

        return False

    def resolve_removals(self, active_de: str | None = None) -> list:
        """
        PATCH 6 & 11: gom hết các entry `<key> = appremove(run=...)` và
        `<key> = fileremove(run=...)` rải rác trong config (hiện tại trong
        khối "Remove package and image", vd systemsettings-KDE/
        image-background) — quét toàn bộ section thay vì hardcode tên
        section, giống resolve_desktop_apply()/resolve_flathub_apps(), để
        hỗ trợ thêm removal khác ở section khác sau này. Giữ nguyên thứ tự
        khai báo trong file vì các lệnh remove có thể phụ thuộc thứ tự chạy
        (vd gỡ package trước khi xoá file liên quan tới package đó).

        Lọc theo active_de nếu có exclude_de / for_de hoặc bảo vệ an toàn
        cho DE (vd: không gỡ systemsettings khi chọn KDE).
        """
        out = []
        for sec_name in self.order:
            for key, raw, _group in self._entries(sec_name):
                pv = classify(key, raw)
                if pv.type == "FUNCTION" and pv.value.get("name") in ("appremove", "fileremove", "command"):
                    resolved = self.resolve_function(pv.value)
                    run_cmd = resolved.get("run")
                    ex_de = resolved.get("exclude_de")
                    f_de = resolved.get("for_de")
                    if self._is_de_excluded(active_de, ex_de, f_de, key=key, run_cmd=run_cmd or ""):
                        continue
                    if run_cmd:
                        entry = {
                            "section": sec_name,
                            "key": key,
                            "type": pv.value.get("name"),
                            "run": run_cmd,
                        }
                        if ex_de:
                            entry["exclude_de"] = ex_de
                        if f_de:
                            entry["for_de"] = f_de
                        out.append(entry)
        return out

    def resolve_installers(self, active_de: str | None = None) -> list:
        """
        PATCH 10 & 11: gom hết các entry `<key> = installer(run=...)` rải rác
        trong config (hiện tại trong [Call-gnome-apps] cho gnome-system-
        monitor / gnome-disk-utility) — quét toàn bộ section, giống
        resolve_removals()/PATCH 6, để hỗ trợ thêm installer() ở section
        khác sau này mà không cần sửa lại đây.

        Ngữ nghĩa: "run" là lệnh shell cài package (thường "apt-get install
        -y <pkg>") chạy TRONG chroot lúc build, sau khi toàn bộ DE/icon/
        keyboard/extra package đã cài xong — đảm bảo gói phụ thuộc đã có
        sẵn trước khi cài package bổ sung này. Không dùng file .sh riêng,
        không hardcode trong workflow YAML: desktop.sh đọc trực tiếp từ
        /tmp/hcl-resolved.json (giống removals).

        Lọc theo active_de nếu có exclude_de / for_de.
        """
        out = []
        for sec_name in self.order:
            # [Call-gnome-apps] installers chỉ chạy khi DE là GNOME
            if sec_name.lower() == "call-gnome-apps":
                is_gnome = (active_de or "").strip().lower() == "gnome"
                gnome_apps_val = None
                if "my-version-os-base" in self.sections:
                    kv = self._kv("my-version-os-base")
                    if "gnome-apps" in kv:
                        gnome_apps_val = classify("gnome-apps", kv["gnome-apps"]).value
                if not is_gnome or gnome_apps_val is False:
                    continue
            for key, raw, _group in self._entries(sec_name):
                pv = classify(key, raw)
                if pv.type == "FUNCTION" and pv.value.get("name") == "installer":
                    resolved = self.resolve_function(pv.value)
                    run_cmd = resolved.get("run")
                    ex_de = resolved.get("exclude_de")
                    f_de = resolved.get("for_de")
                    if self._is_de_excluded(active_de, ex_de, f_de, key=key, run_cmd=run_cmd or ""):
                        continue
                    if run_cmd:
                        entry = {
                            "section": sec_name,
                            "key": key,
                            "type": "installer",
                            "run": run_cmd,
                        }
                        if ex_de:
                            entry["exclude_de"] = ex_de
                        if f_de:
                            entry["for_de"] = f_de
                        out.append(entry)
        return out

    def resolve_file_copies(self) -> list:
        """
        PATCH 7: gom hết các entry `<key> = filecopy(source=..., target=...)`
        rải rác trong config (hiện tại chỉ có "xfce4-desktop-config" trong
        khối "Apply image background") — quét toàn bộ section thay vì
        hardcode tên section/key, giống resolve_removals()/PATCH 6, để hỗ
        trợ thêm filecopy(source=,target=) khác sau này mà không cần sửa
        lại đây.

        BUG ĐÃ SỬA: entry này trước đây KHÔNG được resolve bởi bất kỳ hàm
        nào trong resolve_all() — resolve_desktop_apply() (PATCH 4) chỉ
        quét function tên "apply", không phải "filecopy", nên
        "xfce4-desktop-config" hoàn toàn biến mất khỏi kết quả (không có
        trong --emit-json, không có trong --emit-env), dù validate_every_
        entry() không báo lỗi gì (filecopy đã có trong FUNCTION_NAMES từ
        trước) và source (./iso-config/xfce/xfce4-desktop.xml) có tồn tại
        thật trong repo. desktop.sh vì vậy không có cách nào biết cần copy
        file này vào đâu — file iso-config/xfce/xfce4-desktop.xml chưa
        từng được apply lên ISO dù khai báo trong config.ini "có vẻ đúng".

        Chỉ nhận dạng kwargs (source=...) — filecopy(<path>) dạng
        positional-arg (chỉ có target trên rootfs, xem nhánh "arg" trong
        resolve_function) là ngữ nghĩa khác (đích cho filetheme() ghép
        riêng), không thuộc nhóm copy-nguồn-vào-đích này.

        PATCH 9: gom thêm cả copy(source=..., rename=..., target=...) —
        cùng nhóm ngữ nghĩa "copy nguồn trong repo vào đích trên rootfs"
        với filecopy(source=,target=), chỉ khác copy() có thêm "rename".
        Gom chung vào đây (thay vì thêm 1 hàm resolve_copies() riêng) để
        to_env_lines() không phải nhớ thêm 1 danh sách nữa — mọi nơi gọi
        resolve_file_copies() lấy được cả filecopy() lẫn copy() theo đúng
        thứ tự khai báo trong file. "rename" giữ None nếu entry là
        filecopy() (không có rename) để phân biệt với copy() không đặt
        rename (basename gốc của source) — cả 2 trường hợp "resolved_target"
        đều đã tính sẵn ở resolve_function().
        """
        out = []
        for sec_name in self.order:
            for key, raw, _group in self._entries(sec_name):
                pv = classify(key, raw)
                if pv.type != "FUNCTION" or pv.value.get("name") not in ("filecopy", "copy"):
                    continue
                fn = pv.value
                if "kwargs" not in fn or "source" not in fn["kwargs"]:
                    continue
                resolved = self.resolve_function(fn)
                out.append({
                    "section": sec_name,
                    "key": key,
                    "type": fn["name"],
                    "source": resolved.get("source"),
                    "rename": resolved.get("rename"),
                    "target": resolved.get("target"),
                    "resolved_target": resolved.get("resolved_target"),
                    "is_dir": resolved.get("is_dir", False),
                })
        return out

    def validate_every_entry(self):
        for sec_name in self.order:
            for key, raw, _group in self._entries(sec_name):
                try:
                    classify(key, raw)
                except HclError as e:
                    self.diags.append(Diagnostic(
                        "error", f"[{sec_name}] {key} = {raw!r} — {e}"))

    def resolve_all(self, de_override: str | None = None) -> dict:
        result = {}
        result["base_profile"] = self.resolve_my_version_os_base()
        bp = result["base_profile"]
        kp = bp.get("kernel_profile") or {}
        
        de_info = self.resolve_desktop_environment()
        result["desktop_environment"] = de_info
        
        de_from_env_section = de_info.get("active_desktop") or ""
        active_de = (de_override or de_from_env_section or kp.get("desktop") or "").strip().lower()

        result["package_groups"] = self.resolve_package_groups()
        result["apt_repository"] = self.resolve_apt_repository()
        result["desktop_apply"] = self.resolve_desktop_apply()
        result["flathub_apps"] = self.resolve_flathub_apps(active_de=active_de)
        result["removals"] = self.resolve_removals(active_de=active_de)
        result["installers"] = self.resolve_installers(active_de=active_de)
        result["file_copies"] = self.resolve_file_copies()
        # PATCH 13: gom GNOME extensions và tweaks — chỉ xuất khi DE=gnome
        result["gnome_extensions"] = self.resolve_gnome_extensions(active_de=active_de)
        result["gnome_tweaks"] = self.resolve_gnome_tweaks(active_de=active_de)
        if "customization" in self.sections:
            result["customization"] = {
                k: self.resolve_value(k, v) for k, v, _ in self._entries("customization")
            }
        result["easter_egg"] = self.resolve_easter_egg()
        welcome_kv = self._kv_scan("linkhyggshi-welcome")
        result["welcome"] = {
            k: self.resolve_value(k, v) for k, v in welcome_kv.items()
        }
        plymouth_kv = self._kv_scan("linkplymouth")
        plymouth_kv.update(self._kv_scan("linkhyggshi-plymouth"))
        result["plymouth"] = {
            k: self.resolve_value(k, v) for k, v in plymouth_kv.items()
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

    kp_swap = kp.get("swap") if isinstance(kp, dict) else None
    swap = (kp_swap if isinstance(kp_swap, dict) and kp_swap.get("mode") != "off" else None) or bp.get("swap") or {}
    swap_mode = swap.get("mode") or "off"
    swap_mb = int(swap.get("mb", 0))
    put("SWAP_MODE", swap_mode)
    put("SWAP_MB", swap_mb)

    fw_pkgs = bp.get("firmware_packages") or {}
    put("FIRMWARE_ENABLED", str(bool(bp.get("firmware_enabled"))).lower())
    put("FIRMWARE_PACKAGES", " ".join(sorted(fw_pkgs.keys())))

    # [config-setup-postpartum-care] (out["config"], resolved qua tham chiếu
    # ${config-setup-postpartum-care} trong [my-version-os-base]) — trước đây
    # dict này được resolve nhưng CHƯA BAO GIỜ export ra env, nên squashfs-
    # max-compression (và Time-zone/lang/stylexfce) chỉ nằm chết trong
    # /tmp/hcl-resolved.json, iso.sh/desktop.sh không đọc được. Export đúng
    # squashfs-max-compression ở đây để scripts/iso.sh dùng.
    cfg = bp.get("config") if isinstance(bp.get("config"), dict) else {}
    sq_max = str(bool(cfg.get("squashfs-max-compression", bp.get("squashfs-max-compression")))).lower()
    put("SQUASHFS_MAX_COMPRESSION", sq_max)

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
                # Bỏ qua các key boolean là feature flag / toggle cấu hình
                # (vd install-flatpak, install-flathub, theme-*-enabled),
                # KHÔNG phải tên gói apt — tránh lọt vào ALL_PACKAGES ->
                # HCL_PACKAGES -> EXTRA_PACKAGES -> apt-get install gây lỗi:
                # "E: Unable to locate package install-flatpak / install-flathub".
                if k in ("install-flatpak", "install-flathub") or k.startswith("theme-"):
                    continue
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

    # PATCH 4: export apply() (background image + lệnh postinstall tuỳ
    # chọn) ứng với DE đang active. Key trong config.ini đặt tên kiểu
    # "xfce4" (không phải "xfce" như DE_GROUP_EXACT dùng cho tên gói) nên
    # match bằng cách bỏ số ở cuối key rồi so lower-case, thay vì exact-match.
    desktop_apply_entries = resolved.get("desktop_apply", [])
    active_apply = next(
        (a for a in desktop_apply_entries
         if re.sub(r"\d+$", "", str(a.get("key", "")).lower()) == de),
        None,
    )
    put("DESKTOP_APPLY_TARGET", active_apply.get("target") if active_apply else "")
    put("DESKTOP_APPLY_RUNCOMMAND", active_apply.get("runcommand") if active_apply else "")

    # PATCH 5: export danh sách app Flathub cần cài (flathubinstall(...) đã
    # gom ở resolve_flathub_apps()). install-flatpak/install-flathub (2 key
    # boolean nằm trong [package], dưới header "install flatpak and
    # flathub" -> group đó, KHÔNG phải "(ungrouped)") trước giờ được
    # resolve nhưng CHƯA BAO GIỜ export — desktop.sh không có cách nào biết
    # có nên bật Flatpak/Flathub remote hay không, giống bug
    # squashfs-max-compression đã sửa ở trên. Qué toàn bộ group thay vì
    # đoán tên group, vì tên group phụ thuộc đúng text của comment header.
    install_flatpak = any(g.get("install-flatpak") is True for g in pkg_groups.values())
    install_flathub = any(g.get("install-flathub") is True for g in pkg_groups.values())
    put("FLATPAK_ENABLED", str(install_flatpak).lower())
    put("FLATHUB_ENABLED", str(install_flathub).lower())

    gnome_apps_call = bp.get("gnome_apps")
    is_gnome_active = (de == "gnome")
    gnome_apps_enabled = is_gnome_active and (gnome_apps_call is not False and gnome_apps_call is not None)
    put("GNOME_APPS_ENABLED", str(gnome_apps_enabled).lower())

    # PATCH 13: export GNOME extensions
    gnome_ext_call = bp.get("gnome_extensions")
    gnome_ext_enabled = is_gnome_active and (gnome_ext_call is not False and gnome_ext_call is not None)
    put("GNOME_EXTENSIONS_ENABLED", str(gnome_ext_enabled).lower())
    gnome_extensions = resolved.get("gnome_extensions", []) if gnome_ext_enabled else []
    put("GNOME_EXT_COUNT", len(gnome_extensions))
    for idx, e in enumerate(gnome_extensions, start=1):
        put(f"GNOME_EXT_{idx}_KEY", e.get("key"))
        put(f"GNOME_EXT_{idx}_RUN", e.get("run"))

    # PATCH 13: export GNOME tweaks
    gnome_tweak_call = bp.get("gnome_tweak")
    gnome_tweak_enabled = is_gnome_active and (gnome_tweak_call is not False and gnome_tweak_call is not None)
    put("GNOME_TWEAK_ENABLED", str(gnome_tweak_enabled).lower())
    gnome_tweaks = resolved.get("gnome_tweaks", []) if gnome_tweak_enabled else []
    put("GNOME_TWEAK_COUNT", len(gnome_tweaks))
    for idx, t in enumerate(gnome_tweaks, start=1):
        put(f"GNOME_TWEAK_{idx}_KEY", t.get("key"))
        put(f"GNOME_TWEAK_{idx}_RUN", t.get("run"))

    flathub_apps = resolved.get("flathub_apps", [])
    if de != "gnome":
        flathub_apps = [
            app for app in flathub_apps
            if not app.startswith("org.gnome.") and app != "com.mattjakeman.ExtensionManager"
        ]
    put("FLATHUB_APPS", " ".join(flathub_apps))

    # PATCH 6: export danh sách lệnh appremove()/fileremove() (gom ở
    # resolve_removals()) — trước đây các entry này chỉ bị validate (kwarg
    # "run") rồi bỏ xó, không có cách nào để scripts/desktop.sh hay
    # scripts/iso.sh biết cần chạy lệnh gỡ package / xoá file nào. Export
    # theo số thứ tự (giống APT_REPO_{idx}) để giữ nguyên thứ tự khai báo,
    # cộng REMOVE_COUNT để script build lặp qua đúng số lệnh mà không cần
    # đoán mò biến nào tồn tại.
    removals = resolved.get("removals", [])
    put("REMOVE_COUNT", len(removals))
    for idx, r in enumerate(removals, start=1):
        put(f"REMOVE_{idx}_KEY", r.get("key"))
        put(f"REMOVE_{idx}_TYPE", r.get("type"))
        put(f"REMOVE_{idx}_RUN", r.get("run"))

    # PATCH 10: export danh sách lệnh installer(run=...) (gom ở
    # resolve_installers()). Cùng cơ chế PATCH 6/removals: gom sẵn trong
    # JSON, desktop.sh đọc và chạy trong chroot — không cần file .sh riêng
    # hay bước workflow YAML mới. Export theo số thứ tự + INSTALLER_COUNT
    # để desktop.sh lặp qua đúng số lệnh.
    installers = resolved.get("installers", [])
    put("INSTALLER_COUNT", len(installers))
    for idx, r in enumerate(installers, start=1):
        put(f"INSTALLER_{idx}_KEY", r.get("key"))
        put(f"INSTALLER_{idx}_RUN", r.get("run"))

    # PATCH 7: export các entry filecustom(...) trong [customization]
    # (Calamares settings/branding/modules, logo Plymouth, ảnh nền desktop,
    # ảnh nền GRUB). Cùng bug y hệt [config-setup-postpartum-care] và
    # install-flatpak/install-flathub đã sửa ở trên: resolve_all() đã gom
    # đúng section "customization" vào resolved["customization"] (xem
    # resolve_all()), nhưng to_env_lines() trước đây KHÔNG BAO GIỜ đọc key
    # này ra — nghĩa là toàn bộ "lệnh" filecustom() khai trong config.ini
    # (linksettingscalamares/linkbrandingcalamares/linkmodulescalamares/
    # linkimagelogo/linkimagebackground/linkgrubbackground) chỉ nằm chết
    # trong --emit-json, KHÔNG có biến env nào để scripts/*.sh đọc ra mà
    # "ra lệnh" (copy file/patch config) — file .ini khai gì cũng vô nghĩa
    # với build thật, y hệt lý do [package] và customization đã bị coi là
    # "chết" trước khi các PATCH ở trên được thêm. Export theo số thứ tự
    # (giống APT_REPO_{idx}/REMOVE_{idx}) để giữ nguyên thứ tự khai báo và
    # không cần đoán tên biến theo từng key.
    customization = resolved.get("customization", {})
    put("CUSTOM_COUNT", len(customization))
    for idx, (key, val) in enumerate(customization.items(), start=1):
        if not isinstance(val, dict):
            continue
        put(f"CUSTOM_{idx}_KEY", key)
        put(f"CUSTOM_{idx}_TYPE", val.get("call"))
        is_url = bool(val.get("is_url"))
        put(f"CUSTOM_{idx}_IS_URL", str(is_url).lower())
        put(f"CUSTOM_{idx}_PATH", val.get("url") if is_url else val.get("path"))

    # PATCH 8: export các entry filecopy(source=,target=) đã gom ở
    # resolve_file_copies()/PATCH 7. Cùng lý do PATCH 7 export
    # "customization" ở trên: resolve_all() gom đúng vào
    # resolved["file_copies"], nhưng to_env_lines() không đọc key này ra
    # thì desktop.sh (chạy trong chroot, không đọc trực tiếp config.ini)
    # không có biến nào để biết cần copy gì — lệnh filecopy() trong .ini
    # coi như không tồn tại với build thật. Export theo số thứ tự (giống
    # CUSTOM_{idx}/APT_REPO_{idx}) để desktop.sh lặp qua mà không cần biết
    # trước có bao nhiêu entry hay tên key gì.
    #
    # PATCH 9: thêm FILECOPY_{idx}_TYPE (filecopy/copy) và
    # FILECOPY_{idx}_RESOLVED_TARGET (target đã ghép sẵn tên file cuối
    # cùng — basename(source) với filecopy(), hoặc rename với copy() nếu
    # có khai) để desktop.sh không phải tự tính lại basename/rename bằng
    # shell — chỉ cần `cp "$SOURCE" "$RESOLVED_TARGET"` là đủ cho cả 2 loại.
    file_copies = resolved.get("file_copies", [])
    put("FILECOPY_COUNT", len(file_copies))
    for idx, fc in enumerate(file_copies, start=1):
        put(f"FILECOPY_{idx}_KEY", fc.get("key"))
        put(f"FILECOPY_{idx}_TYPE", fc.get("type"))
        put(f"FILECOPY_{idx}_SOURCE", fc.get("source"))
        put(f"FILECOPY_{idx}_RENAME", fc.get("rename"))
        put(f"FILECOPY_{idx}_TARGET", fc.get("target"))
        put(f"FILECOPY_{idx}_RESOLVED_TARGET", fc.get("resolved_target"))

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

    plymouth = (
        resolved.get("plymouth", {}).get("linkplymouth")
        or resolved.get("plymouth", {}).get("linkhyggshi-plymouth")
        or {}
    )
    put("PLYMOUTH_SCRIPT", plymouth.get("file", ""))
    put("PLYMOUTH_ACTION", plymouth.get("action", ""))

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

    de_info = resolved.get("desktop_environment") or {}
    build_all = de_info.get("build_all_github_actions", False)
    put("HCL_BUILD_ALL_DESKTOPS", str(build_all).lower())
    put("HCL_DESKTOPS_MATRIX", " ".join(de_info.get("desktops_to_build", [])))

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
    if swap_mode:
        lines.append(f"SWAP_MODE={swap_mode}")
        lines.append(f"SWAP_MB={swap_mb}")
    lines.append(f"SQUASHFS_MAX_COMPRESSION={sq_max}")

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
            "input 'desktop': xfce/cinnamon/kde/lxqt/gnome/mate/cli/all). Khi được "
            "truyền, giá trị này thay thế [kernel.<Edition>].desktop tĩnh trong "
            "config.ini làm nguồn lọc package_groups active — tránh gói của DE "
            "không được chọn (vd Cinnamon) lọt vào HCL_PACKAGES khi build DE khác (vd XFCE)."
        ),
    )
    ap.add_argument(
        "--print-matrix-json",
        action="store_true",
        help="In mảng JSON danh sách desktop matrix cần build (dành cho GitHub Actions matrix strategy)"
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
        resolved = resolver.resolve_all(de_override=args.de_override)
    except HclError as e:
        print(f"::error::[HCL resolve] {e}", file=sys.stderr)
        sys.exit(1)

    if args.print_matrix_json:
        de_info = resolved.get("desktop_environment") or {}
        de_override = (args.de_override or "").strip().lower()
        if de_override == "all":
            matrix_list = ["xfce", "kde", "gnome", "cinnamon", "mate", "lxqt"]
        elif de_override and de_override not in ("auto", "none"):
            matrix_list = [de_override]
        elif de_info.get("build_all_github_actions"):
            matrix_list = de_info.get("desktops_to_build") or ["xfce", "kde", "gnome", "cinnamon", "mate", "lxqt"]
        else:
            active = de_info.get("active_desktop") or "xfce"
            matrix_list = [active]
        matrix_json = json.dumps(matrix_list)
        print(matrix_json)
        gh_output = os.environ.get("GITHUB_OUTPUT")
        if gh_output:
            try:
                with open(gh_output, "a", encoding="utf-8") as f:
                    f.write(f"matrix={matrix_json}\n")
                    f.write(f"is_matrix={'true' if len(matrix_list) > 1 else 'false'}\n")
            except Exception:
                pass
        sys.exit(0)

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
