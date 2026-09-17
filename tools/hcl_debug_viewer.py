#!/usr/bin/env python3
"""
hcl_debug_viewer_qt.py — GUI viewer (PyQt6) cho HCL resolved config + build debug logs.

Ban Qt cua tools/hcl_debug_viewer.py (tkinter) — giao dien dep hon, mo hon,
threading khong lam treo UI, tim kiem khong pha format.

Cai dat:
    pip install PyQt6

Dung:
    python3 tools/hcl_debug_viewer_qt.py
    python3 tools/hcl_debug_viewer_qt.py --root /path/to/repo
"""

from __future__ import annotations

import argparse
import glob
import importlib.util
import os
import re
import subprocess
import sys

from PyQt6.QtCore import Qt, QThread, pyqtSignal
from PyQt6.QtGui import QColor, QFont, QTextCharFormat, QTextCursor, QTextDocument
from PyQt6.QtWidgets import (
    QApplication,
    QButtonGroup,
    QCheckBox,
    QComboBox,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QListWidget,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QRadioButton,
    QSplitter,
    QTabWidget,
    QTableWidget,
    QTableWidgetItem,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

# ---------------------------------------------------------------------------
# Palette / constants
# ---------------------------------------------------------------------------

BG = "#0f1117"
BG2 = "#1a1d27"
BG3 = "#252836"
ACCENT = "#7c6af7"
ACCT2 = "#a78bfa"
FG = "#e0e0e0"
FGDIM = "#888888"
BORDER = "#2d2f3e"
BTNBG = "#2a2d3e"
BTNHOV = "#3a3d52"

LOG_COLORS = {
    "error": "#ff6b6b",
    "warning": "#ffd166",
    "ok": "#06d6a0",
    "info": "#a8dadc",
    "debug": "#aaaaaa",
    "default": FG,
}

HCL_COLORS = {
    "section": "#a78bfa",
    "key": "#7dd3fc",
    "string": "#fca5a5",
    "number": "#93c5fd",
    "bool_true": "#34d399",
    "bool_false": "#f87171",
    "diag_error": "#ff6b6b",
}

MONO_FONT = "Consolas, 'JetBrains Mono', 'DejaVu Sans Mono', monospace"

STYLE_SHEET = f"""
QWidget {{
    background-color: {BG2};
    color: {FG};
    font-family: "Segoe UI", "Ubuntu", sans-serif;
    font-size: 10.5pt;
}}
QMainWindow {{
    background-color: {BG};
}}
#TopBar {{
    background-color: {BG};
    border-bottom: 1px solid {BORDER};
}}
#TitleLabel {{
    color: {ACCT2};
    font-size: 13pt;
    font-weight: 600;
}}
#RootLabel {{
    color: {FGDIM};
    font-family: Consolas, monospace;
}}
QStatusBar {{
    background-color: {BG3};
    color: {FGDIM};
    font-family: Consolas, monospace;
}}
QTabWidget::pane {{
    border: none;
    background-color: {BG};
}}
QTabBar::tab {{
    background-color: {BG3};
    color: {FGDIM};
    padding: 8px 16px;
    border: none;
}}
QTabBar::tab:selected {{
    background-color: {BG2};
    color: {ACCT2};
    border-bottom: 2px solid {ACCENT};
}}
QListWidget, QTableWidget, QTextEdit, QLineEdit, QComboBox {{
    background-color: {BG3};
    color: {FG};
    border: 1px solid {BORDER};
    border-radius: 4px;
}}
QListWidget::item:selected, QTableWidget::item:selected {{
    background-color: {ACCENT};
    color: white;
}}
QHeaderView::section {{
    background-color: {BG2};
    color: {ACCT2};
    padding: 4px;
    border: none;
    font-weight: 600;
}}
QPushButton {{
    background-color: {BTNBG};
    color: {FG};
    border: none;
    border-radius: 4px;
    padding: 6px 14px;
}}
QPushButton:hover {{
    background-color: {BTNHOV};
}}
QPushButton#PrimaryBtn {{
    background-color: {ACCENT};
    color: white;
    font-weight: 600;
}}
QPushButton#PrimaryBtn:hover {{
    background-color: {ACCT2};
}}
QCheckBox, QRadioButton {{
    spacing: 6px;
}}
QToolTip {{
    background-color: {BG3};
    color: {FG};
    border: 1px solid {BORDER};
}}
"""


# ---------------------------------------------------------------------------
# Helpers (giu nguyen logic tu ban tkinter)
# ---------------------------------------------------------------------------

def find_repo_root(start: str = ".") -> str:
    d = os.path.abspath(start)
    for _ in range(8):
        if os.path.exists(os.path.join(d, ".github")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return os.path.abspath(start)


def classify_line(line: str) -> str:
    lo = line.lower()
    if re.search(r"\berror\b|e: unable|e: .*failed|fatal", lo):
        return "error"
    if re.search(r"\bwarning\b|warn\b", lo):
        return "warning"
    if re.search(r"\bok\b|da |xong|success|done|installed", lo):
        return "ok"
    if line.startswith("+ ") or line.startswith("==="):
        return "debug"
    return "default"


def mono(size: int = 10) -> QFont:
    f = QFont("Consolas")
    f.setStyleHint(QFont.StyleHint.Monospace)
    f.setPointSize(size)
    return f


# ---------------------------------------------------------------------------
# Background threads (khong lam treo UI khi resolve config / doc log / chay parser)
# ---------------------------------------------------------------------------

class HclThread(QThread):
    ok = pyqtSignal(dict, list, list)
    err = pyqtSignal(str)

    def __init__(self, root_dir: str, parent=None):
        super().__init__(parent)
        self.root_dir = root_dir

    def run(self):
        cfg = os.path.join(self.root_dir, "iso-config", "config", "config.ini")
        prsr = os.path.join(self.root_dir, "tools", "hcl_parser.py")
        if not os.path.exists(cfg):
            self.err.emit(f"Khong tim thay:\n  {cfg}")
            return
        if not os.path.exists(prsr):
            self.err.emit(f"Khong tim thay parser:\n  {prsr}")
            return
        try:
            spec = importlib.util.spec_from_file_location("hcl_parser", prsr)
            if spec is None or spec.loader is None:
                self.err.emit(f"Không thể tạo module spec từ:\n  {prsr}")
                return
            mod = importlib.util.module_from_spec(spec)
            sys.modules["hcl_parser"] = mod
            spec.loader.exec_module(mod)
            sections = mod.read_sections(cfg)
            resolver = mod.Resolver(sections, root=self.root_dir)
            resolver.validate_every_entry()
            resolved = resolver.resolve_all()
            env_lines = mod.to_env_lines(resolved)
            diags = resolver.diags
            self.ok.emit(resolved, list(diags), list(env_lines))
        except Exception as exc:
            self.err.emit(str(exc))


class LogThread(QThread):
    ok = pyqtSignal(list)
    err = pyqtSignal(str)

    def __init__(self, path: str, parent=None):
        super().__init__(parent)
        self.path = path

    def run(self):
        try:
            with open(self.path, encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
            tagged = [(ln.rstrip("\n"), classify_line(ln)) for ln in lines]
            self.ok.emit(tagged)
        except Exception as exc:
            self.err.emit(str(exc))


class RunThread(QThread):
    done = pyqtSignal(str, str, int)

    def __init__(self, cmd: list[str], cwd: str, parent=None):
        super().__init__(parent)
        self.cmd = cmd
        self.cwd = cwd

    def run(self):
        try:
            p = subprocess.run(
                self.cmd, capture_output=True, text=True, cwd=self.cwd, timeout=30
            )
            self.done.emit(p.stdout, p.stderr, p.returncode)
        except Exception as exc:
            self.done.emit("", str(exc), 1)


# ---------------------------------------------------------------------------
# Main window
# ---------------------------------------------------------------------------

class MainWindow(QMainWindow):
    def __init__(self, root_dir: str):
        super().__init__()
        self.root_dir = root_dir
        self.hcl_resolved: dict = {}
        self.log_lines: list[tuple[str, str]] = []
        self.env_rows: list[tuple[str, str]] = []
        self._threads: list[QThread] = []  # giu tham chieu de thread khong bi GC giua chung

        self.setWindowTitle("Hyggshi OS — HCL Debug Viewer")
        self.resize(1350, 820)
        self.setMinimumSize(950, 620)

        self._build_ui()
        self._load_initial()

    # ------------------------------------------------------------------
    # UI construction
    # ------------------------------------------------------------------

    def _build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        outer = QVBoxLayout(central)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.setSpacing(0)

        outer.addWidget(self._build_topbar())

        self.tabs = QTabWidget()
        outer.addWidget(self.tabs, 1)
        self.tabs.addTab(self._build_hcl_tab(), "  HCL Resolved  ")
        self.tabs.addTab(self._build_logs_tab(), "  Build Logs  ")
        self.tabs.addTab(self._build_run_tab(), "  Chạy Parser  ")
        self.tabs.addTab(self._build_env_tab(), "  Env Output  ")

        self.statusBar().showMessage("Sẵn sàng.")

    def _build_topbar(self) -> QWidget:
        bar = QFrame()
        bar.setObjectName("TopBar")
        bar.setFixedHeight(46)
        lay = QHBoxLayout(bar)
        lay.setContentsMargins(14, 0, 14, 0)

        title = QLabel("Hyggshi OS  ·  HCL Debug Viewer")
        title.setObjectName("TitleLabel")
        lay.addWidget(title)

        self.root_lbl = QLabel(self.root_dir)
        self.root_lbl.setObjectName("RootLabel")
        lay.addWidget(self.root_lbl)
        lay.addStretch(1)

        change_btn = QPushButton("Đổi repo…")
        change_btn.clicked.connect(self._change_root)
        lay.addWidget(change_btn)

        return bar

    # -- Tab 1: HCL Resolved -------------------------------------------------

    def _build_hcl_tab(self) -> QWidget:
        w = QWidget()
        root = QHBoxLayout(w)
        root.setContentsMargins(4, 4, 4, 4)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        root.addWidget(splitter)

        self.sec_list = QListWidget()
        self.sec_list.setMaximumWidth(220)
        self.sec_list.setFont(mono(10))
        self.sec_list.itemSelectionChanged.connect(self._on_section_select)
        splitter.addWidget(self.sec_list)

        right = QWidget()
        rlay = QVBoxLayout(right)
        rlay.setContentsMargins(4, 0, 0, 0)

        tb = QHBoxLayout()
        reload_btn = QPushButton("Reload config.ini")
        reload_btn.setObjectName("PrimaryBtn")
        reload_btn.clicked.connect(self._load_hcl)
        tb.addWidget(reload_btn)

        self.hcl_search = QLineEdit()
        self.hcl_search.setPlaceholderText("Tìm kiếm…")
        self.hcl_search.setMaximumWidth(240)
        self.hcl_search.textChanged.connect(self._hcl_search)
        tb.addWidget(self.hcl_search)
        tb.addStretch(1)

        self.hcl_diag = QLabel("")
        tb.addWidget(self.hcl_diag)
        rlay.addLayout(tb)

        self.hcl_text = QTextEdit()
        self.hcl_text.setReadOnly(True)
        self.hcl_text.setFont(mono(11))
        self.hcl_text.setLineWrapMode(QTextEdit.LineWrapMode.NoWrap)
        rlay.addWidget(self.hcl_text, 1)

        splitter.addWidget(right)
        splitter.setStretchFactor(1, 1)

        return w

    # -- Tab 2: Build Logs ----------------------------------------------------

    def _build_logs_tab(self) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)
        lay.setContentsMargins(4, 4, 4, 4)

        tb = QHBoxLayout()
        tb.addWidget(QLabel("File log:"))
        self.log_combo = QComboBox()
        self.log_combo.setMinimumWidth(320)
        self.log_combo.setFont(mono(10))
        self.log_combo.currentTextChanged.connect(self._load_log)
        tb.addWidget(self.log_combo)

        refresh_btn = QPushButton("Refresh")
        refresh_btn.clicked.connect(self._refresh_logs)
        tb.addWidget(refresh_btn)

        self.log_filter_group = QButtonGroup(self)
        for i, (val, lbl) in enumerate(
            [("all", "Tất cả"), ("error", "Lỗi"), ("warning", "Warning"), ("ok", "OK")]
        ):
            rb = QRadioButton(lbl)
            if val != "all":
                rb.setStyleSheet(f"color: {LOG_COLORS.get(val, FG)};")
            rb.setChecked(val == "all")
            rb.setProperty("value", val)
            rb.toggled.connect(self._apply_filter)
            self.log_filter_group.addButton(rb, i)
            tb.addWidget(rb)

        self.log_search = QLineEdit()
        self.log_search.setPlaceholderText("Tìm…")
        self.log_search.setMaximumWidth(220)
        self.log_search.textChanged.connect(self._apply_filter)
        tb.addWidget(self.log_search)
        tb.addStretch(1)

        self.log_count = QLabel("")
        tb.addWidget(self.log_count)
        lay.addLayout(tb)

        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setFont(mono(10))
        self.log_text.setLineWrapMode(QTextEdit.LineWrapMode.NoWrap)
        lay.addWidget(self.log_text, 1)

        return w

    # -- Tab 3: Run Parser ------------------------------------------------

    def _build_run_tab(self) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)
        lay.setContentsMargins(8, 8, 8, 8)

        row1 = QHBoxLayout()
        row1.addWidget(QLabel("config.ini:"))
        self.cfg_edit = QLineEdit(
            os.path.join(self.root_dir, "iso-config", "config", "config.ini")
        )
        self.cfg_edit.setFont(mono(10))
        row1.addWidget(self.cfg_edit, 1)
        browse_btn = QPushButton("…")
        browse_btn.setMaximumWidth(36)
        browse_btn.clicked.connect(self._browse_cfg)
        row1.addWidget(browse_btn)
        lay.addLayout(row1)

        row2 = QHBoxLayout()
        row2.addWidget(QLabel("--de-override:"))
        self.de_combo = QComboBox()
        self.de_combo.addItems(["xfce", "cinnamon", "kde", "lxqt", "gnome", "mate", "cli"])
        row2.addWidget(self.de_combo)
        self.strict_chk = QCheckBox("--strict")
        self.strict_chk.setChecked(True)
        row2.addWidget(self.strict_chk)
        row2.addStretch(1)
        lay.addLayout(row2)

        row3 = QHBoxLayout()
        run_btn = QPushButton("Chạy Parser + Validate")
        run_btn.setObjectName("PrimaryBtn")
        run_btn.clicked.connect(self._run_parser)
        row3.addWidget(run_btn)

        emit_json_btn = QPushButton("Emit JSON")
        emit_json_btn.clicked.connect(self._emit_json)
        row3.addWidget(emit_json_btn)

        emit_env_btn = QPushButton("Emit Env")
        emit_env_btn.clicked.connect(self._emit_env)
        row3.addWidget(emit_env_btn)

        self.run_lbl = QLabel("")
        self.run_lbl.setStyleSheet(f"color: {ACCT2};")
        row3.addWidget(self.run_lbl)
        row3.addStretch(1)
        lay.addLayout(row3)

        self.run_text = QTextEdit()
        self.run_text.setReadOnly(True)
        self.run_text.setFont(mono(10))
        self.run_text.setStyleSheet(f"background-color: #080b10;")
        self.run_text.setLineWrapMode(QTextEdit.LineWrapMode.NoWrap)
        lay.addWidget(self.run_text, 1)

        return w

    # -- Tab 4: Env Output -------------------------------------------------

    def _build_env_tab(self) -> QWidget:
        w = QWidget()
        lay = QVBoxLayout(w)
        lay.setContentsMargins(4, 4, 4, 4)

        tb = QHBoxLayout()
        self.env_search = QLineEdit()
        self.env_search.setPlaceholderText("Tìm biến KEY=VALUE")
        self.env_search.setMaximumWidth(320)
        self.env_search.textChanged.connect(self._env_search)
        tb.addWidget(self.env_search)
        tb.addStretch(1)
        self.env_count = QLabel("")
        tb.addWidget(self.env_count)
        lay.addLayout(tb)

        self.env_table = QTableWidget(0, 2)
        self.env_table.setHorizontalHeaderLabels(["KEY", "VALUE"])
        self.env_table.horizontalHeader().setSectionResizeMode(
            0, QHeaderView.ResizeMode.ResizeToContents
        )
        self.env_table.horizontalHeader().setSectionResizeMode(
            1, QHeaderView.ResizeMode.Stretch
        )
        self.env_table.verticalHeader().setVisible(False)
        self.env_table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.env_table.setFont(mono(10))
        lay.addWidget(self.env_table, 1)

        return w

    # ------------------------------------------------------------------
    # Init
    # ------------------------------------------------------------------

    def _load_initial(self):
        self._refresh_logs()
        self._load_hcl()

    # ------------------------------------------------------------------
    # Text-edit rendering helpers (khong pha format khi highlight tim kiem)
    # ------------------------------------------------------------------

    @staticmethod
    def _append(edit: QTextEdit, text: str, color: str | None = None):
        cursor = edit.textCursor()
        cursor.movePosition(QTextCursor.MoveOperation.End)
        fmt = QTextCharFormat()
        fmt.setForeground(QColor(color or FG))
        cursor.setCharFormat(fmt)
        cursor.insertText(text)

    def _highlight_matches(self, edit: QTextEdit, query: str):
        selections = []
        edit.setExtraSelections([])
        if not query:
            return
        doc = edit.document()
        fmt = QTextCharFormat()
        fmt.setBackground(QColor("#3a3a00"))
        fmt.setForeground(QColor("#ffffff"))
        cursor = doc.find(query)
        while not cursor.isNull():
            sel = QTextEdit.ExtraSelection()
            sel.cursor = cursor
            sel.format = fmt
            selections.append(sel)
            cursor = doc.find(query, cursor)
        edit.setExtraSelections(selections)

    # ------------------------------------------------------------------
    # HCL tab logic
    # ------------------------------------------------------------------

    def _load_hcl(self):
        self.statusBar().showMessage("Đang resolve config.ini…")
        th = HclThread(self.root_dir)
        th.ok.connect(self._on_hcl_ok)
        th.err.connect(self._on_hcl_err)
        th.finished.connect(lambda: self._threads.remove(th) if th in self._threads else None)
        self._threads.append(th)
        th.start()

    def _on_hcl_ok(self, resolved: dict, diags: list, env_lines: list):
        self.hcl_resolved = resolved
        self.sec_list.clear()
        for sec in resolved:
            self.sec_list.addItem(sec)
        self._render_hcl(resolved)
        self._load_env(env_lines)

        errors = [d for d in diags if getattr(d, "level", "") == "error"]
        warnings = [d for d in diags if getattr(d, "level", "") == "warning"]
        if errors:
            lbl, col = f"{len(errors)} error · {len(warnings)} warning", LOG_COLORS["error"]
        elif warnings:
            lbl, col = f"{len(warnings)} warning", LOG_COLORS["warning"]
        else:
            lbl, col = "OK — không có lỗi", LOG_COLORS["ok"]
        self.hcl_diag.setText(lbl)
        self.hcl_diag.setStyleSheet(f"color: {col};")
        self.statusBar().showMessage(f"Config loaded — {lbl}")

    def _on_hcl_err(self, msg: str):
        self.hcl_text.clear()
        self._append(self.hcl_text, f"LỖI:\n{msg}", HCL_COLORS["diag_error"])
        self.hcl_diag.setText("LỖI")
        self.hcl_diag.setStyleSheet(f"color: {LOG_COLORS['error']};")
        self.statusBar().showMessage("Lỗi khi load HCL.")

    def _rv(self, edit: QTextEdit, v, indent: int = 0):
        pad = "  " * indent
        if isinstance(v, dict):
            self._append(edit, "{\n")
            for k, vi in v.items():
                self._append(edit, f"{pad}  ")
                self._append(edit, f'"{k}"', HCL_COLORS["key"])
                self._append(edit, ": ")
                self._rv(edit, vi, indent + 1)
                self._append(edit, ",\n")
            self._append(edit, f"{pad}" + "}")
        elif isinstance(v, list):
            if not v:
                self._append(edit, "[]")
            else:
                self._append(edit, "[\n")
                for item in v:
                    self._append(edit, f"{pad}  ")
                    self._rv(edit, item, indent + 1)
                    self._append(edit, ",\n")
                self._append(edit, f"{pad}]")
        elif isinstance(v, bool):
            self._append(edit, str(v).lower(), HCL_COLORS["bool_true"] if v else HCL_COLORS["bool_false"])
        elif isinstance(v, str):
            self._append(edit, f'"{v}"', HCL_COLORS["string"])
        elif isinstance(v, (int, float)):
            self._append(edit, str(v), HCL_COLORS["number"])
        elif v is None:
            self._append(edit, "null", HCL_COLORS["bool_false"])
        else:
            self._append(edit, str(v))

    def _render_hcl(self, data: dict, section_filter: str | None = None):
        edit = self.hcl_text
        edit.clear()
        self._append(edit, "{\n")
        for sec, val in data.items():
            if section_filter and sec != section_filter:
                continue
            self._append(edit, f'  "{sec}"', HCL_COLORS["section"])
            self._append(edit, ": ")
            self._rv(edit, val, 1)
            self._append(edit, ",\n\n")
        self._append(edit, "}\n")

    def _on_section_select(self):
        items = self.sec_list.selectedItems()
        if items:
            self._render_hcl(self.hcl_resolved, section_filter=items[0].text())
            self._hcl_search(self.hcl_search.text())

    def _hcl_search(self, text: str = ""):
        self._highlight_matches(self.hcl_text, self.hcl_search.text().strip())

    # ------------------------------------------------------------------
    # Logs tab logic
    # ------------------------------------------------------------------

    def _refresh_logs(self):
        log_dir = os.path.join(self.root_dir, "log")
        files: list[str] = []
        for pat in ["**/*.log", "**/*.txt", "**/*.json"]:
            files.extend(glob.glob(os.path.join(log_dir, pat), recursive=True))
        files = sorted(set(files))
        rels = [os.path.relpath(f, self.root_dir) for f in files]

        current = self.log_combo.currentText()
        self.log_combo.blockSignals(True)
        self.log_combo.clear()
        self.log_combo.addItems(rels)
        self.log_combo.blockSignals(False)
        if rels:
            if current in rels:
                self.log_combo.setCurrentText(current)
            else:
                self.log_combo.setCurrentIndex(0)
                self._load_log(self.log_combo.currentText())
        self.statusBar().showMessage(f"Tìm thấy {len(files)} file log.")

    def _load_log(self, rel: str):
        if not rel:
            return
        path = os.path.join(self.root_dir, rel)
        if not os.path.exists(path):
            return
        self.statusBar().showMessage(f"Đang tải {os.path.basename(path)}…")
        th = LogThread(path)
        th.ok.connect(self._display_log)
        th.err.connect(lambda m: self.statusBar().showMessage(f"Lỗi đọc log: {m}"))
        th.finished.connect(lambda: self._threads.remove(th) if th in self._threads else None)
        self._threads.append(th)
        th.start()

    def _display_log(self, tagged: list):
        self.log_lines = tagged
        self._apply_filter()
        self.statusBar().showMessage(f"Đã tải {len(tagged)} dòng.")

    def _current_log_filter(self) -> str:
        btn = self.log_filter_group.checkedButton()
        return btn.property("value") if btn else "all"

    def _apply_filter(self):
        filt = self._current_log_filter()
        search = self.log_search.text().strip().lower()
        edit = self.log_text
        edit.clear()
        shown = 0
        for line, tag in self.log_lines:
            if filt != "all" and tag != filt:
                continue
            if search and search not in line.lower():
                continue
            self._append(edit, line + "\n", LOG_COLORS.get(tag, LOG_COLORS["default"]))
            shown += 1
        self.log_count.setText(f"{shown} / {len(self.log_lines)} dòng")
        self._highlight_matches(edit, search)

    # ------------------------------------------------------------------
    # Run Parser tab logic
    # ------------------------------------------------------------------

    def _browse_cfg(self):
        path, _ = QFileDialog.getOpenFileName(self, "Chọn config.ini", self.root_dir)
        if path:
            self.cfg_edit.setText(path)

    def _run_parser(self):
        self.run_text.clear()
        self.run_lbl.setText("Đang chạy…")
        cfg = self.cfg_edit.text()
        de = self.de_combo.currentText()
        strict = self.strict_chk.isChecked()
        prsr = os.path.join(self.root_dir, "tools", "hcl_parser.py")
        cmd = [sys.executable, prsr, cfg, "--root", self.root_dir, "--de-override", de]
        if strict:
            cmd.append("--strict")
        self._start_run(cmd)

    def _emit_json(self):
        path, _ = QFileDialog.getSaveFileName(
            self, "Emit JSON", os.path.join(self.root_dir, "log", "hcl-resolved.json"),
            "JSON (*.json)",
        )
        if path:
            self._run_cmd_extra("--emit-json", path)

    def _emit_env(self):
        path, _ = QFileDialog.getSaveFileName(
            self, "Emit Env", os.path.join(self.root_dir, "log", "hcl-build.env"),
            "Env (*.env);;All (*.*)",
        )
        if path:
            self._run_cmd_extra("--emit-env", path)

    def _run_cmd_extra(self, flag: str, path: str):
        cfg = self.cfg_edit.text()
        de = self.de_combo.currentText()
        strict = ["--strict"] if self.strict_chk.isChecked() else []
        prsr = os.path.join(self.root_dir, "tools", "hcl_parser.py")
        cmd = [sys.executable, prsr, cfg, "--root", self.root_dir, "--de-override", de, flag, path] + strict
        self.run_lbl.setText("Đang xuất…")
        self._start_run(cmd)

    def _start_run(self, cmd: list[str]):
        th = RunThread(cmd, self.root_dir)
        th.done.connect(self._display_run)
        th.finished.connect(lambda: self._threads.remove(th) if th in self._threads else None)
        self._threads.append(th)
        th.start()

    def _display_run(self, stdout: str, stderr: str, code: int):
        edit = self.run_text
        if stdout:
            for line in stdout.splitlines():
                self._append(edit, line + "\n", LOG_COLORS.get(classify_line(line)))
        if stderr:
            self._append(edit, "\n--- stderr ---\n", LOG_COLORS["warning"])
            for line in stderr.splitlines():
                self._append(edit, line + "\n", LOG_COLORS["error"])
        icon = "OK" if code == 0 else "LỖI"
        self._append(
            edit, f"\n[{icon}] Exit code: {code}\n",
            LOG_COLORS["ok"] if code == 0 else LOG_COLORS["error"],
        )
        edit.moveCursor(QTextCursor.MoveOperation.End)
        self.run_lbl.setText("Thành công (exit 0)" if code == 0 else f"Lỗi (exit {code})")

    # ------------------------------------------------------------------
    # Env tab logic
    # ------------------------------------------------------------------

    def _load_env(self, env_lines: list):
        rows = []
        for line in env_lines:
            if "=" in line:
                k, _, v = line.partition("=")
                rows.append((k.strip(), v.strip()))
        self.env_rows = rows
        self._env_populate(rows)

    def _env_populate(self, rows: list):
        table = self.env_table
        table.setRowCount(len(rows))
        for r, (k, v) in enumerate(rows):
            is_err = "ERROR" in k or "FAIL" in v.upper()
            k_item = QTableWidgetItem(k)
            v_item = QTableWidgetItem(v)
            if is_err:
                k_item.setForeground(QColor(LOG_COLORS["error"]))
                v_item.setForeground(QColor(LOG_COLORS["error"]))
            table.setItem(r, 0, k_item)
            table.setItem(r, 1, v_item)
        self.env_count.setText(f"{len(rows)} biến")

    def _env_search(self, text: str):
        q = text.strip().lower()
        filtered = [(k, v) for k, v in self.env_rows if q in k.lower() or q in v.lower()]
        self._env_populate(filtered)

    # ------------------------------------------------------------------
    # Change repo
    # ------------------------------------------------------------------

    def _change_root(self):
        d = QFileDialog.getExistingDirectory(self, "Chọn thư mục repo Hyggshi OS", self.root_dir)
        if not d:
            return
        self.root_dir = d
        self.root_lbl.setText(d)
        self.cfg_edit.setText(os.path.join(d, "iso-config", "config", "config.ini"))
        self.log_combo.clear()
        self._refresh_logs()
        self._load_hcl()

    def closeEvent(self, event):
        for th in list(self._threads):
            if th.isRunning():
                th.wait(500)
        super().closeEvent(event)


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="HCL Debug Viewer (Qt)")
    ap.add_argument("--root", default=None)
    args = ap.parse_args()
    root_dir = os.path.abspath(
        args.root or find_repo_root(os.path.join(os.path.dirname(__file__), ".."))
    )

    app = QApplication(sys.argv)
    app.setStyleSheet(STYLE_SHEET)
    win = MainWindow(root_dir=root_dir)
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
