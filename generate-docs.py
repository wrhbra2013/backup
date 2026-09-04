#!/usr/bin/env python3
"""Generate static documentation site for backup project shell scripts."""

import os
import re
import shutil
import textwrap
from pathlib import Path
from html import escape

PROJECT_DIR = Path(__file__).parent
OUTPUT_DIR = PROJECT_DIR / "docs"
SCRIPTS_DIR = OUTPUT_DIR / "scripts"
FERRAMENTAS_DIR = PROJECT_DIR / "ferramentas"

HEADER_COMMANDS = {
    "dnf": "Package Manager",
    "yum": "Package Manager",
    "rpm": "Package Manager",
    "systemctl": "System Service",
    "journalctl": "System Logs",
    "mount": "Filesystem",
    "umount": "Filesystem",
    "mkfs": "Filesystem",
    "git": "Git",
    "wget": "Download",
    "curl": "Download",
    "sed": "Text Processing",
    "awk": "Text Processing",
    "grep": "Text Processing",
    "xrandr": "Display",
    "rsync": "Sync/Backup",
    "cp": "File Operations",
    "mv": "File Operations",
    "rm": "File Operations",
    "mkdir": "File Operations",
    "chmod": "Permissions",
    "chown": "Permissions",
    "pip3": "Python",
    "python3": "Python",
    "npm": "Node.js",
    "pm2": "Node.js",
    "nginx": "Web Server",
    "certbot": "SSL/TLS",
    "ufw": "Firewall",
    "firewall-cmd": "Firewall",
    "ssh": "SSH",
    "scp": "SSH",
    "dnf-3": "Package Manager",
    "flatpak": "Package Manager",
    "snap": "Package Manager",
    "xorriso": "ISO Tool",
    "mksquashfs": "ISO Tool",
    "createrepo_c": "Repository",
    "createrepo": "Repository",
    "dracut": "Initramfs",
    "grub2-mkrescue": "Bootloader",
    "grub2-mkconfig": "Bootloader",
    "grubby": "Bootloader",
    "audit2allow": "SELinux",
    "checkmodule": "SELinux",
    "semodule": "SELinux",
    "virt-sysprep": "Virtualization",
    "virt-sparsify": "Virtualization",
    "lb": "Live Build",
    "xdotool": "XFCE",
    "xfconf-query": "XFCE",
    "gsettings": "GNOME",
    "tee": "File Operations",
    "touch": "File Operations",
    "ln": "File Operations",
    "tar": "Archive",
    "gzip": "Archive",
    "unzip": "Archive",
    "parted": "Disk",
    "lsblk": "Disk",
    "blkid": "Disk",
    "timedatectl": "System",
    "localectl": "System",
    "hostnamectl": "System",
    "sysctl": "Kernel",
    "modprobe": "Kernel",
    "udevadm": "Kernel",
    "useradd": "User Management",
    "passwd": "User Management",
    "usermod": "User Management",
}

CATEGORY_ORDER = [
    "Package Manager",
    "System Service",
    "System Logs",
    "Filesystem",
    "Git",
    "Download",
    "Text Processing",
    "Display",
    "Sync/Backup",
    "File Operations",
    "Permissions",
    "Python",
    "Node.js",
    "Web Server",
    "SSL/TLS",
    "Firewall",
    "SSH",
    "ISO Tool",
    "Repository",
    "Initramfs",
    "Bootloader",
    "SELinux",
    "Virtualization",
    "Live Build",
    "XFCE",
    "GNOME",
    "Archive",
    "Disk",
    "System",
    "Kernel",
    "User Management",
]

CATEGORY_META = [
    ("iso", "ISO & LiveCD", "🏗️", "79,70,229"),
    ("config", "Configuração & Otimização", "⚙️", "14,165,233"),
    ("packaging", "Empacotamento", "📦", "139,92,246"),
    ("vm", "Virtualização & VM", "🖥️", "16,185,129"),
    ("servers", "Servidores & Serviços", "🌐", "245,158,11"),
    ("bluetooth", "Bluetooth", "🔵", "59,130,246"),
    ("sync", "Sincronização & Docs", "🔄", "239,68,68"),
    ("sku", "SKU & E-commerce", "🛒", "236,72,153"),
]

CATEGORY_RULES = [
    ("iso", ["build_iso", "build_offline", "build_ol9", "build_backup", "create_iso", "gerar_iso", "rebuild_ol9", "oracle.sh"]),
    ("packaging", ["appimage2rpm", "create_rpm", "manager_repo_sh"]),
    ("config", ["ol9-audit", "ol9-full-setup", "otimizar", "setup-xfce-tiling", "setup-zram", "xrandr-config", "remove_old_kernels", "auto_fix_powerprofiles", "fix_boot_ol9", "fix-repos", "oracle_config"]),
    ("vm", ["control.sh", "restore-snapshot", "setup-api-debian"]),
    ("servers", ["node.sh", "manut.sh", "debian.sh"]),
    ("bluetooth", ["bt-auto", "bt-ctl"]),
    ("sync", ["git-sync", "update-appimages", "update-docs", "atualizar"]),
    ("sku", ["gerar_sku"]),
]

DIR_SHORT = {
    "root": "raiz",
    "system_scripts": "sys",
    "vm_scripts": "vm",
    "bluetooth": "bt",
}


def _is_just_decor(text):
    """Return True when a header line is only decorative banner characters."""
    if not text:
        return True
    return bool(re.fullmatch(r"[\W_]+", text))


def extract_header(filepath):
    """Extract shebang, header comments, usage, and description from a script."""
    content = filepath.read_text(encoding="utf-8", errors="replace")
    lines = content.split("\n")

    shebang = ""
    header_comments = []
    description = ""
    usage = ""
    in_header = True
    header_started = False

    for i, line in enumerate(lines):
        if i == 0 and line.startswith("#!"):
            shebang = line
            continue
        if in_header:
            if line.startswith("#"):
                header_started = True
                stripped = line.lstrip("# ").strip()
                if stripped:
                    header_comments.append(stripped)
                    # Detect usage line
                    if re.search(r"^(Uso|Usage|Modo de usar)", stripped, re.IGNORECASE):
                        usage = stripped
                    # First meaningful comment line is the description
                    if not description and not re.search(r"^(Uso|Usage|Modo de usar)", stripped, re.IGNORECASE):
                        candidate = re.sub(r"[┌┐└┘│╔╗╚╝║═━╰╯╮╭]", "", stripped)
                        candidate = re.sub(r"\s{2,}", " ", candidate).strip()
                        if not _is_just_decor(candidate):
                            description = candidate
            elif line.strip() == "" and header_started:
                header_comments.append("")
            else:
                if header_started:
                    in_header = False

    return {
        "shebang": shebang,
        "header_comments": header_comments,
        "description": description,
        "usage": usage,
        "content": content,
        "lines": lines,
    }


def extract_functions(lines):
    """Extract function definitions from script lines."""
    functions = []
    func_pattern = re.compile(r"^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\s*\)\s*\{")
    for i, line in enumerate(lines):
        m = func_pattern.match(line)
        if m:
            functions.append({"name": m.group(1), "line": i + 1})
    return functions


def extract_variables(lines):
    """Extract configuration variables (UPPERCASE=value at top of script)."""
    variables = []
    var_pattern = re.compile(r'^\s*([A-Z][A-Z0-9_]+)=["\']?(.*?)["\']?\s*(?:#.*)?$')
    seen = set()
    for i, line in enumerate(lines):
        # Only check first 100 lines for config variables
        if i >= 100:
            break
        line = line.strip()
        if not line or line.startswith("#") or "for " in line or "in " in line:
            continue
        m = var_pattern.match(line)
        if m and m.group(1) not in seen:
            val = m.group(2).strip()
            if len(val) > 60:
                val = val[:57] + "..."
            if len(val) > 0:
                variables.append({"name": m.group(1), "value": val})
                seen.add(m.group(1))
    return variables


def extract_commands(lines):
    """Extract commands used in the script, grouped by category."""
    commands = {}
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("#") or stripped.startswith("##"):
            continue
        for cmd, category in HEADER_COMMANDS.items():
            # Match as a command invocation (not part of a word)
            pattern = re.compile(
                r'(?<![a-zA-Z0-9_-])' + re.escape(cmd) + r'(?![a-zA-Z0-9_-])'
            )
            if pattern.search(stripped):
                if category not in commands:
                    commands[category] = set()
                commands[category].add(cmd)

    # Sort commands within categories
    result = {}
    for cat in CATEGORY_ORDER:
        if cat in commands:
            result[cat] = sorted(commands[cat])
    # Add any categories not in CATEGORY_ORDER
    for cat in sorted(commands):
        if cat not in result:
            result[cat] = sorted(commands[cat])

    return result


def extract_packages(lines):
    """Extract package names from dnf/yum install lines."""
    packages = []
    pkg_pattern = re.compile(
        r'(?:dnf|yum)\s+(?:install|groupinstall|remove)\s+(.*?)(?:[;&|]|$)'
    )
    for line in lines:
        m = pkg_pattern.search(line)
        if m:
            pkgs = re.findall(r'(?:^|\s+)([a-zA-Z0-9][a-zA-Z0-9._+-]*[a-zA-Z0-9])(?:\s|$)', m.group(1))
            for p in pkgs:
                if p not in packages and len(p) > 1 and not p.startswith("-"):
                    packages.append(p)
    return packages


def extract_dependencies(lines):
    """Extract required package dependencies from check_pkg / rpm -q patterns."""
    deps = []
    dep_pattern = re.compile(r'["\']([a-zA-Z][a-zA-Z0-9._+-]*)["\']')
    for line in lines:
        if "rpm -q" in line or "check_pkg" in line or "REQUIRED_PKGS" in line:
            for m in dep_pattern.finditer(line):
                pkg = m.group(1)
                if pkg not in deps and len(pkg) > 1:
                    deps.append(pkg)
    return deps


def scan_scripts():
    """Scan all .sh files in the project and extract metadata."""
    scripts = []
    for ext in ["*.sh", "manager_repo_sh"]:
        for path in PROJECT_DIR.rglob(ext):
            # Skip .git directory
            if ".git" in path.parts:
                continue
            if path.parent == OUTPUT_DIR or path.parent == SCRIPTS_DIR:
                continue
            if path.is_file():
                scripts.append(path)

    scripts.sort(key=lambda p: p.relative_to(PROJECT_DIR))

    results = []
    for path in scripts:
        try:
            info = extract_header(path)
            rel_path = path.relative_to(PROJECT_DIR)
            dir_name = str(rel_path.parent)
            if dir_name == ".":
                dir_name = "root"

            info["path"] = path
            info["rel_path"] = str(rel_path)
            info["dir_name"] = dir_name
            info["filename"] = path.name
            info["functions"] = extract_functions(info["lines"])
            info["variables"] = extract_variables(info["lines"])
            info["commands"] = extract_commands(info["lines"])
            info["packages"] = extract_packages(info["lines"])
            info["deps"] = extract_dependencies(info["lines"])
            info["line_count"] = len(info["lines"])
            info["size_kb"] = round(path.stat().st_size / 1024, 1)

            # If no description found, use filename
            if not info["description"]:
                info["description"] = path.name

            results.append(info)
        except Exception as e:
            print(f"  Error processing {path}: {e}")

    return results


def scan_ferramentas():
    """Scan all .html files in ferramentas/ (recursive) and extract TOOL_META comments."""
    if not FERRAMENTAS_DIR.exists():
        return []
    results = []
    for path in sorted(FERRAMENTAS_DIR.rglob("*.html")):
        try:
            content = path.read_text(encoding="utf-8")
            rel_path = path.relative_to(PROJECT_DIR).as_posix()
            meta = {"path": path, "filename": path.name, "rel_path": rel_path}
            match = re.search(r"<!--\s*TOOL_META:\s*(.*?)\s*-->", content)
            if match:
                for pair in match.group(1).split("|"):
                    if "=" in pair:
                        k, v = pair.split("=", 1)
                        meta[k.strip()] = v.strip()
            meta.setdefault("title", path.stem.replace("-", " ").title())
            meta.setdefault("desc", "")
            meta.setdefault("tags", "")
            meta.setdefault("gradient", "#4f46e5,#7c3aed,#22d3ee")
            meta.setdefault("icon", "🔧")
            results.append(meta)
        except Exception as e:
            print(f"  Error processing ferramenta {path}: {e}")
    return results


def make_slug(name):
    """Create a URL-friendly slug from filename."""
    slug = name.replace(".sh", "").replace("_", "-")
    return slug


def classify_script(info):
    """Best-effort classification of a script by purpose (filename rules + dir fallback)."""
    filename = info.get("filename", "")
    for key, patterns in CATEGORY_RULES:
        for pattern in patterns:
            if pattern in filename:
                return key
    fallback = {
        "bluetooth": "bluetooth",
        "vm_scripts": "vm",
        "root": "config",
        "system_scripts": "config",
    }
    return fallback.get(info.get("dir_name", ""), "config")


def get_category(key):
    """Return (label, emoji, color) for a category key, with a sensible default."""
    for k, label, emoji, color in CATEGORY_META:
        if k == key:
            return label, emoji, color
    return key.replace("_", " ").title(), "🔧", "107,114,128"


def count_names_per_script(cats):
    """Count how many times each filename appears across the whole project."""
    counts = {}
    for group in cats.values():
        for s in group:
            counts[s["filename"]] = counts.get(s["filename"], 0) + 1
    return counts


def render_sidebar(cats, active_rel=None, ferramentas=(), base=""):
    """Render the navigation sidebar grouped by category."""
    active_dash = ' class="active"' if active_rel is None else ""
    html = '<div class="sidebar-title">📂 Navegação</div>'
    html += f'<a href="{base}index.html"{active_dash}>📊 Dashboard</a>'

    counts = count_names_per_script(cats)
    for key, label, emoji, _color in CATEGORY_META:
        group = cats.get(key)
        if not group:
            continue
        has_active = active_rel is not None and any(s["rel_path"] == active_rel for s in group)
        open_attr = " open" if has_active or active_rel is None else ""
        html += (
            f'<details class="side-group"{open_attr}><summary>'
            f'<span class="g-emoji">{emoji}</span>{label}'
            f'<span class="g-count">{len(group)}</span></summary>'
        )
        for s in group:
            slug = make_slug(s["filename"])
            active = ' class="active"' if active_rel is not None and s["rel_path"] == active_rel else ""
            cmd_count = sum(len(cmds) for cmds in s["commands"].values())
            dup = dir_marker(s, counts)
            html += (
                f'<a href="{base}scripts/{slug}.html"{active}>{escape(s["filename"])}'
                f'{dup}<span class="s-badge">{cmd_count}</span></a>'
            )
        html += "</details>"

    if ferramentas:
        html += (
            f'<details class="side-group" open><summary>'
            f'<span class="g-emoji">🧰</span>Ferramentas'
            f'<span class="g-count">{len(ferramentas)}</span></summary>'
        )
        for f in ferramentas:
            html += f'<a href="{base}{escape(f["rel_path"])}">{escape(f.get("icon", "🔧"))} {escape(f.get("title", f["filename"]))}</a>'
        html += "</details>"
    return html


def dir_marker(s, name_counts=None):
    """Small dir label shown when a filename appears more than once in the project."""
    if name_counts is None or name_counts.get(s["filename"], 0) <= 1:
        return ""
    short = DIR_SHORT.get(s["dir_name"], s["dir_name"])
    return f'<span class="s-dir">{escape(short)}</span>'


def css_style():
    return """
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, monospace; background: #f5f5f5; color: #1a1a1a; line-height: 1.6; }
.container { max-width: 1200px; margin: 0 auto; padding: 20px; }
h1 { font-size: 1.8rem; margin-bottom: 8px; }
h2 { font-size: 1.3rem; margin: 24px 0 12px; color: #2563eb; border-bottom: 2px solid #e5e7eb; padding-bottom: 6px; }
h3 { font-size: 1rem; margin: 16px 0 8px; color: #374151; }
.subtitle { color: #6b7280; margin-bottom: 20px; font-size: 0.95rem; }
a { color: #2563eb; text-decoration: none; }
a:hover { text-decoration: underline; }
.header-bar { background: #1e293b; color: #fff; padding: 16px 0; margin-bottom: 24px; }
.header-bar .container { display: flex; justify-content: space-between; align-items: center; }
.header-bar h1 { margin: 0; font-size: 1.3rem; }
.header-bar h1 a { color: #fff; }
.header-bar h1 a:hover { text-decoration: none; }
.header-bar .nav a { color: #93c5fd; margin-left: 16px; font-size: 0.9rem; }
.search-box { width: 100%; padding: 10px 14px; border: 2px solid #d1d5db; border-radius: 8px; font-size: 0.95rem; margin-bottom: 20px; outline: none; transition: border-color 0.2s; }
.search-box:focus { border-color: #2563eb; }
table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
th, td { padding: 10px 14px; text-align: left; font-size: 0.9rem; }
th { background: #f8fafc; font-weight: 600; color: #374151; border-bottom: 2px solid #e5e7eb; }
td { border-bottom: 1px solid #f0f0f0; }
tr:hover td { background: #f8fafc; }
.badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 0.75rem; font-weight: 600; margin: 1px 2px; }
.badge-pkg { background: #dcfce7; color: #166534; }
.badge-cmd { background: #dbeafe; color: #1e40af; }
.badge-func { background: #fef3c7; color: #92400e; }
.badge-dir { background: #e5e7eb; color: #374151; }
.tag { display: inline-block; padding: 2px 6px; border-radius: 3px; font-size: 0.7rem; font-weight: 600; background: #e5e7eb; color: #374151; margin: 1px; }
.tag-category { background: #ede9fe; color: #5b21b6; }
.cmd-count { font-size: 0.8rem; color: #6b7280; }
.stat-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 12px; margin-bottom: 24px; }
.stat-card { background: #fff; border-radius: 8px; padding: 16px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); text-align: center; }
.stat-card .num { font-size: 1.8rem; font-weight: 700; color: #2563eb; }
.stat-card .label { font-size: 0.8rem; color: #6b7280; margin-top: 4px; }
.script-page { max-width: 960px; margin: 0 auto; }
.meta-table { width: 100%; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.1); margin-bottom: 20px; }
.meta-table td { padding: 8px 14px; border-bottom: 1px solid #f0f0f0; }
.meta-table td:first-child { font-weight: 600; color: #374151; width: 140px; background: #f8fafc; }
.cmd-group { margin-bottom: 16px; }
.cmd-group-title { font-size: 0.85rem; font-weight: 600; color: #5b21b6; margin-bottom: 6px; }
.cmd-list { display: flex; flex-wrap: wrap; gap: 4px; }
.source-box { margin: 12px 0; }
.source-box textarea { width: 100%; padding: 12px; border: 2px solid #d1d5db; border-radius: 8px; font-family: 'Courier New', monospace; font-size: 0.8rem; line-height: 1.4; background: #1e293b; color: #e5e7eb; resize: vertical; outline: none; }
.source-box textarea:focus { border-color: #2563eb; }
.copy-btn { display: inline-block; padding: 8px 16px; background: #2563eb; color: #fff; border: none; border-radius: 6px; font-size: 0.85rem; cursor: pointer; margin: 8px 4px 4px 0; transition: background 0.2s; }
.copy-btn:hover { background: #1d4ed8; }
.copy-btn.copied { background: #16a34a; }
.download-btn { display: inline-block; padding: 8px 16px; background: #374151; color: #fff; border: none; border-radius: 6px; font-size: 0.85rem; cursor: pointer; margin: 8px 4px 4px 0; transition: background 0.2s; text-decoration: none; }
.download-btn:hover { background: #1f2937; text-decoration: none; }
.func-list { display: flex; flex-wrap: wrap; gap: 6px; margin: 8px 0; }
.func-item { background: #fef3c7; color: #92400e; padding: 3px 10px; border-radius: 4px; font-family: 'Courier New', monospace; font-size: 0.8rem; }
.var-list { display: flex; flex-wrap: wrap; gap: 6px; }
.var-item { background: #f0fdf4; color: #166534; padding: 3px 10px; border-radius: 4px; font-family: 'Courier New', monospace; font-size: 0.78rem; }
.var-item code { font-size: 0.78rem; }
.back-link { display: inline-block; margin-bottom: 16px; color: #2563eb; font-size: 0.9rem; }
.back-link:before { content: "← "; }
.stat-line { font-size: 0.8rem; color: #6b7280; margin-bottom: 12px; }
.layout { display: flex; gap: 24px; align-items: flex-start; }
.sidebar { width: 260px; flex-shrink: 0; background: #fff; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); overflow: hidden; position: sticky; top: 20px; max-height: calc(100vh - 80px); overflow-y: auto; }
.sidebar-title { padding: 12px 16px; font-weight: 700; font-size: 0.85rem; color: #1e293b; background: #f8fafc; border-bottom: 1px solid #e5e7eb; text-transform: uppercase; letter-spacing: 0.5px; }
.sidebar a { display: block; padding: 8px 16px; color: #374151; text-decoration: none; font-size: 0.82rem; border-left: 3px solid transparent; transition: all 0.15s; }
.sidebar a:hover { background: #f1f5f9; border-left-color: #93c5fd; }
.sidebar a.active { background: #eff6ff; border-left-color: #2563eb; color: #1e40af; font-weight: 600; }
.sidebar-group { border-top: 1px solid #f0f0f0; }
.sidebar-group-label { padding: 6px 16px; font-size: 0.7rem; font-weight: 600; color: #9ca3af; text-transform: uppercase; letter-spacing: 0.3px; }
.sidebar a .s-badge { float: right; background: #e5e7eb; color: #374151; padding: 0 6px; border-radius: 3px; font-size: 0.65rem; font-weight: 600; line-height: 1.6; }
.main-content { flex: 1; min-width: 0; }
.tool-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 20px; margin: 16px 0 28px; }
.tool-card { display: flex; flex-direction: column; background: #fff; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.08); overflow: hidden; text-decoration: none; color: inherit; transition: transform 0.2s, box-shadow 0.2s; position: relative; }
.tool-card:hover { transform: translateY(-4px); box-shadow: 0 8px 24px rgba(0,0,0,0.12); }
.tool-banner { height: 100px; display: flex; align-items: center; justify-content: center; }
.tool-emoji { font-size: 3rem; filter: drop-shadow(0 2px 6px rgba(0,0,0,0.3)); }
.tool-body { padding: 16px; flex: 1; }
.tool-body h3 { font-size: 1rem; color: #1e293b; margin-bottom: 6px; }
.tool-body p { font-size: 0.82rem; color: #6b7280; line-height: 1.4; margin-bottom: 8px; }
.tool-tags { display: flex; flex-wrap: wrap; gap: 4px; }
.tool-arrow { position: absolute; top: 16px; right: 16px; font-size: 1.2rem; color: #9ca3af; transition: color 0.2s; }
.tool-card:hover .tool-arrow { color: #2563eb; }
.header-bar .nav a.active { color: #fff; font-weight: 600; }
.cat-chips { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 16px; }
.cat-chip { --c: #6b7280; display: inline-flex; align-items: center; gap: 6px; padding: 6px 14px; border: 2px solid #e5e7eb; border-radius: 999px; background: #fff; color: #374151; font-size: 0.8rem; font-weight: 600; cursor: pointer; transition: all 0.15s; }
.cat-chip:hover { border-color: #cbd5e1; transform: translateY(-1px); }
.cat-chip.active { border-color: var(--c); color: var(--c); }
.cat-chip .chip-count { background: #f1f5f9; border-radius: 999px; padding: 0 8px; font-size: 0.7rem; font-weight: 600; color: #6b7280; }
.cat-chip.active .chip-count { background: rgba(148,163,184,.2); }
.table-meta { display: flex; justify-content: space-between; align-items: center; gap: 12px; margin: 12px 0; flex-wrap: wrap; }
.table-meta .visible-count { font-size: 0.8rem; color: #6b7280; }
.table-wrap { overflow-x: auto; }
.badge-cat { display: inline-block; padding: 2px 10px; border-radius: 999px; font-size: 0.72rem; font-weight: 600; white-space: nowrap; }
.desc-cell { max-width: 340px; color: #4b5563; }
.actions { white-space: nowrap; }
.empty-row td { text-align: center; padding: 32px; color: #9ca3af; font-size: 0.9rem; }
.side-group { border-top: 1px solid #f0f0f0; }
.side-group summary { display: flex; align-items: center; gap: 8px; padding: 10px 16px; font-size: 0.72rem; font-weight: 700; color: #6b7280; text-transform: uppercase; letter-spacing: 0.3px; cursor: pointer; list-style: none; user-select: none; }
.side-group summary::-webkit-details-marker { display: none; }
.side-group summary::marker { content: ""; }
.side-group:hover summary, .side-group[open] summary { color: #5b21b6; background: #faf5ff; }
.side-group .g-count { margin-left: auto; background: #e5e7eb; color: #6b7280; border-radius: 999px; padding: 0 8px; font-size: 0.65rem; line-height: 1.8; font-weight: 600; }
.side-group[open] .g-count { background: #ede9fe; color: #5b21b6; }
.side-group .g-emoji { font-size: 0.85rem; }
.side-group a .s-dir { font-size: 0.62rem; color: #9ca3af; background: #f1f5f9; padding: 0 5px; border-radius: 3px; margin-left: 4px; }
@media (max-width: 800px) { .layout { flex-direction: column; } .sidebar { width: 100%; position: static; max-height: none; } .cat-chips { gap: 6px; } }
"""


def render_index(scripts, cats, ferramentas=None):
    """Render the dashboard index page with category chips, search, and filter table."""
    if ferramentas is None:
        ferramentas = []
    total_scripts = len(scripts)
    total_categories = len(cats)
    total_commands = sum(len([c for cat in s["commands"].values() for c in cat]) for s in scripts)
    total_functions = sum(len(s["functions"]) for s in scripts)
    total_lines = sum(s["line_count"] for s in scripts)

    cat_index = {item[0]: i for i, item in enumerate(CATEGORY_META)}
    name_counts = count_names_per_script(cats)
    scripts_sorted = sorted(
        scripts,
        key=lambda s: (cat_index.get(s.get("category", "config"), 99), s["filename"].lower()),
    )

    chips_html = (
        '<button type="button" class="cat-chip active" data-cat="" '
        f'onclick="setCategory(\'\')">Todas <span class="chip-count">{total_scripts}</span></button>'
    )
    for key, label, emoji, color in CATEGORY_META:
        if key not in cats or not cats[key]:
            continue
        chips_html += (
            f'<button type="button" class="cat-chip" data-cat="{key}" style="--c:rgb({color})" '
            f'onclick="setCategory(\'{key}\')">{emoji} {label} '
            f'<span class="chip-count">{len(cats[key])}</span></button>'
        )

    rows_html = ""
    for s in scripts_sorted:
        slug = make_slug(s["filename"])
        cmd_count = sum(len(cmds) for cmds in s["commands"].values())
        func_count = len(s["functions"])

        cat = s.get("category", "config")
        clabel, cemoji, ccolor = get_category(cat)
        dup = dir_marker(s, name_counts)

        cmd_badges = ""
        for _cat, cmds in list(s["commands"].items())[:3]:
            for c in cmds[:2]:
                cmd_badges += f'<span class="badge badge-cmd">{escape(c)}</span>'
        if cmd_count > 6:
            cmd_badges += f'<span class="tag">+{cmd_count - 6} mais</span>'

        pkg_count = len(s["packages"]) + len(s["deps"])
        pkg_badge = f'<span class="badge badge-pkg">{pkg_count}</span>' if pkg_count > 0 else ""

        desc = s["description"]
        desc_short = desc if len(desc) <= 90 else desc[:90].rstrip() + "…"

        rows_html += f"""<tr data-cat="{cat}">
  <td><a href="scripts/{slug}.html"><strong>{escape(s["filename"])}</strong></a>{dup}</td>
  <td class="desc-cell">{escape(desc_short)}</td>
  <td><span class="badge badge-cat" style="background:rgba({ccolor},.12);color:rgb({ccolor})">{cemoji} {clabel}</span></td>
  <td>{cmd_badges}{pkg_badge}</td>
  <td class="cmd-count">{cmd_count} cmd · {func_count} fn · {s["line_count"]} lin</td>
  <td class="actions">
    <a href="scripts/{slug}.desktop" download class="tag" title="Baixar .desktop">🖥️</a>
    <a href="scripts/{slug}.html" class="tag" title="Abrir página">📄</a>
  </td>
</tr>"""

    ferramentas_cards = ""
    for f in ferramentas:
        gradient = f.get("gradient", "#4f46e5,#7c3aed,#22d3ee")
        colors = [c.strip() for c in gradient.split(",")]
        grad_css = f"linear-gradient(135deg, {', '.join(colors)})" if len(colors) >= 2 else gradient
        tags_html = "".join(f'<span class="tag">{escape(t.strip())}</span>' for t in f.get("tags", "").split(",") if t.strip())
        ferramentas_cards += f"""<a href="{escape(f['rel_path'])}" class="tool-card">
  <div class="tool-banner" style="background: {grad_css}">
    <span class="tool-emoji">{escape(f.get('icon', '🔧'))}</span>
  </div>
  <div class="tool-body">
    <h3>{escape(f.get('title', f['filename']))}</h3>
    <p>{escape(f.get('desc', ''))}</p>
    <div class="tool-tags">{tags_html}</div>
  </div>
  <span class="tool-arrow">→</span>
</a>"""

    sidebar_html = render_sidebar(cats, ferramentas=ferramentas, base="")

    html = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' https://api.github.com https://raw.githubusercontent.com;">
<link rel="icon" href="/favicon.ico" sizes="any">
<title>Backup Scripts — Dashboard</title>
<style>{css_style()}</style>
</head>
<body>
<div class="header-bar">
  <div class="container">
    <h1><a href="index.html">📜 Backup Scripts</a></h1>
    <div class="nav">
      <a href="index.html" class="active">Dashboard</a>
      <a href="https://github.com/wrhbra2013/backup" target="_blank" rel="noopener">GitHub</a>
    </div>
  </div>
</div>
<div class="container">
  <h1>Dashboard de Scripts</h1>
  <p class="subtitle">Repositório de scripts de Linux, LiveCD, automação e ferramentas</p>

  <div class="stat-grid">
    <div class="stat-card"><div class="num">{total_scripts}</div><div class="label">Scripts</div></div>
    <div class="stat-card"><div class="num">{total_categories}</div><div class="label">Categorias</div></div>
    <div class="stat-card"><div class="num">{total_commands}</div><div class="label">Comandos</div></div>
    <div class="stat-card"><div class="num">{total_functions}</div><div class="label">Funções</div></div>
    <div class="stat-card"><div class="num">{total_lines:,}</div><div class="label">Linhas de código</div></div>
  </div>

  {'<h2 style="margin-top:2rem">🧰 Ferramentas HTML</h2><div class="tool-grid">' + ferramentas_cards + '</div>' if ferramentas_cards else ''}

  <div class="layout">
    <div class="sidebar">
      {sidebar_html}
    </div>
    <div class="main-content">
      <h2>📦 Scripts por categoria</h2>
      <div class="cat-chips">{chips_html}</div>

      <input type="text" class="search-box" id="search" placeholder="Pesquisar scripts, comandos, descrições..." oninput="applyFilters()">
      <div class="table-meta">
        <span class="visible-count" id="visible-count">{total_scripts} de {total_scripts} scripts</span>
        <span class="visible-count">Ordenado por categoria e nome</span>
      </div>

      <div class="table-wrap">
        <table id="script-table">
          <thead><tr><th>Script</th><th>Descrição</th><th>Categoria</th><th>Comandos / Pacotes</th><th>Info</th><th>Ações</th></tr></thead>
          <tbody>{rows_html}<tr id="empty-state" class="empty-row" style="display:none"><td colspan="6">Nenhum script encontrado. Ajuste a busca ou o filtro de categoria.</td></tr></tbody>
        </table>
      </div>
    </div>
  </div>
</div>

<script>
var currentCat = '';
function setCategory(cat) {{
  currentCat = (currentCat === cat) ? '' : cat;
  var chips = document.querySelectorAll('.cat-chip');
  for (var i = 0; i < chips.length; i++) {{
    chips[i].classList.toggle('active', chips[i].getAttribute('data-cat') === currentCat);
  }}
  applyFilters();
}}
function applyFilters() {{
  var term = document.getElementById('search').value.toLowerCase();
  var rows = document.querySelectorAll('#script-table tbody tr[data-cat]');
  var visible = 0;
  for (var i = 0; i < rows.length; i++) {{
    var row = rows[i];
    var text = row.textContent.toLowerCase();
    var matchTerm = !term || text.indexOf(term) !== -1;
    var matchCat = !currentCat || row.getAttribute('data-cat') === currentCat;
    var show = matchTerm && matchCat;
    row.style.display = show ? '' : 'none';
    if (show) visible++;
  }}
  document.getElementById('empty-state').style.display = visible ? 'none' : '';
  var count = document.getElementById('visible-count');
  if (count) count.textContent = visible + ' de ' + rows.length + ' scripts';
}}
</script>
</body>
</html>"""
    return html


def render_script_page(s, cats, ferramentas=None):
    """Render individual script page."""
    if ferramentas is None:
        ferramentas = []
    slug = make_slug(s["filename"])

    clabel, cemoji, ccolor = get_category(s.get("category", "config"))
    cat_badge = f'<span class="badge badge-cat" style="background:rgba({ccolor},.12);color:rgb({ccolor})">{cemoji} {clabel}</span>'

    # Description from header comments
    desc_html = ""
    if s["header_comments"]:
        desc_html = '<div class="meta-table"><table>'
        for line in s["header_comments"]:
            if line.strip():
                desc_html += f"<tr><td colspan='2'>{escape(line)}</td></tr>"
            else:
                desc_html += f"<tr><td colspan='2'>&nbsp;</td></tr>"
        desc_html += "</table></div>"

    # Metadata
    meta_html = """<div class="meta-table"><table>"""
    meta_html += f'<tr><td>Arquivo</td><td><code>{escape(s["rel_path"])}</code></td></tr>'
    meta_html += f'<tr><td>Shebang</td><td><code>{escape(s["shebang"])}</code></td></tr>'
    meta_html += f'<tr><td>Tamanho</td><td>{s["size_kb"]} KB · {s["line_count"]} linhas</td></tr>'
    if s["usage"]:
        meta_html += f'<tr><td>Uso</td><td><code>{escape(s["usage"])}</code></td></tr>'
    meta_html += "</table></div>"

    # Functions
    funcs_html = ""
    if s["functions"]:
        funcs_html = "<h2>Funções</h2><div class='func-list'>"
        for f in s["functions"]:
            funcs_html += f'<span class="func-item">{escape(f["name"])}() <span style="opacity:0.5">linha {f["line"]}</span></span>'
        funcs_html += "</div>"

    # Variables
    vars_html = ""
    if s["variables"]:
        vars_html = "<h2>Variáveis de Configuração</h2><div class='var-list'>"
        for v in s["variables"]:
            vars_html += f'<span class="var-item"><code>{escape(v["name"])}</code> = <code>{escape(v["value"])}</code></span>'
        vars_html += "</div>"

    # Commands by category
    cmds_html = "<h2>Comandos Utilizados</h2>"
    if s["commands"]:
        for cat, cmds in s["commands"].items():
            cmds_html += f'<div class="cmd-group"><div class="cmd-group-title">{escape(cat)}</div><div class="cmd-list">'
            for c in cmds:
                cmds_html += f'<span class="badge badge-cmd">{escape(c)}</span>'
            cmds_html += "</div></div>"
    else:
        cmds_html += "<p>Nenhum comando específico detectado.</p>"

    # Packages
    pkgs_html = ""
    all_pkgs = s["packages"] + s["deps"]
    if all_pkgs:
        pkgs_html = "<h2>Pacotes / Dependências</h2><div class='cmd-list'>"
        for p in sorted(set(all_pkgs)):
            pkgs_html += f'<span class="badge badge-pkg">{escape(p)}</span>'
        pkgs_html += "</div>"

    # Source code
    source_escaped = escape(s["content"])
    # Determine desktop file path relative to scripts dir
    desktop_rel = f"{slug}.desktop"

    menu_html = render_sidebar(cats, active_rel=s["rel_path"], ferramentas=ferramentas, base="../")

    html = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:;">
<link rel="icon" href="/favicon.ico" sizes="any">
<title>{escape(s["filename"])} — Script Details</title>
<style>{css_style()}</style>
</head>
<body>
<div class="header-bar">
  <div class="container">
    <h1><a href="../index.html">📜 Backup Scripts</a></h1>
    <div class="nav">
      <a href="../index.html">Dashboard</a>
    </div>
  </div>
</div>
<div class="container">
  <div class="layout">
    <div class="sidebar">
      {menu_html}
    </div>
    <div class="main-content script-page">
      <a href="../index.html" class="back-link">Voltar ao Dashboard</a>

      <h1>{escape(s["filename"])}</h1>
      <p class="subtitle">{cat_badge} <span>{escape(s["description"])}</span></p>

      {desc_html}
      {meta_html}
      {funcs_html}
      {vars_html}
      {cmds_html}
      {pkgs_html}

      <h2>Código Fonte</h2>
      <div class="source-box">
        <textarea id="source-code" rows="20" readonly spellcheck="false">{source_escaped}</textarea>
        <div>
          <button class="copy-btn" onclick="copySource()" id="copy-btn">📋 Copiar código</button>
          <button class="copy-btn" onclick="downloadSource()" id="dl-btn">💾 Download .sh</button>
          <a href="{desktop_rel}" class="download-btn" download>▶️ Abrir no Terminal (.desktop)</a>
        </div>
      </div>
    </div>
  </div>
</div>

<script>
function copySource() {{
  var textarea = document.getElementById('source-code');
  textarea.select();
  textarea.setSelectionRange(0, 999999);
  document.execCommand('copy');
  var btn = document.getElementById('copy-btn');
  btn.textContent = '✅ Copiado!';
  btn.classList.add('copied');
  setTimeout(function() {{
    btn.textContent = '📋 Copiar código';
    btn.classList.remove('copied');
  }}, 2000);
}}

function downloadSource() {{
  var content = document.getElementById('source-code').value;
  var blob = new Blob([content], {{type: 'application/x-shellscript'}});
  var url = URL.createObjectURL(blob);
  var a = document.createElement('a');
  a.href = url;
  a.download = '{escape(s["filename"])}';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
  var btn = document.getElementById('dl-btn');
  btn.textContent = '✅ Baixado!';
  setTimeout(function() {{
    btn.textContent = '💾 Download .sh';
  }}, 2000);
}}
</script>
</body>
</html>"""
    return html


def render_desktop(s):
    """Generate .desktop file for a script."""
    abs_path = str(s["path"].resolve())
    return f"""[Desktop Entry]
Type=Application
Name={s["filename"]}
Comment={s["description"]}
Exec=x-terminal-emulator -e bash -c '{abs_path}; echo ""; echo "=== Script finalizado. Pressione Enter para fechar ==="; read'
Terminal=true
Icon=terminal
Categories=Development;System;
"""


def generate():
    """Main generator function."""
    print("Scanning scripts...")
    scripts = scan_scripts()
    print(f"  Found {len(scripts)} scripts")

    print("Scanning ferramentas...")
    ferramentas = scan_ferramentas()
    print(f"  Found {len(ferramentas)} ferramentas")

    # Classify scripts by purpose and group them for the menu
    for s in scripts:
        s["category"] = classify_script(s)
    cats = {}
    for s in scripts:
        cats.setdefault(s["category"], []).append(s)

    # Clean output directory
    if OUTPUT_DIR.exists():
        shutil.rmtree(OUTPUT_DIR)
    SCRIPTS_DIR.mkdir(parents=True)

    print("Generating index.html...")
    index_html = render_index(scripts, cats, ferramentas)
    (OUTPUT_DIR / "index.html").write_text(index_html, encoding="utf-8")

    # Generate individual pages
    for s in scripts:
        slug = make_slug(s["filename"])
        page_html = render_script_page(s, cats, ferramentas)
        page_path = SCRIPTS_DIR / f"{slug}.html"
        page_path.write_text(page_html, encoding="utf-8")

        # Generate .desktop file
        desktop_content = render_desktop(s)
        desktop_path = SCRIPTS_DIR / f"{slug}.desktop"
        desktop_path.write_text(desktop_content, encoding="utf-8")

    print(f"  Generated {len(scripts)} individual pages")
    print(f"  Generated {len(scripts)} .desktop files")

    # Mirror ferramentas/ into docs/ferramentas/ (tool pages + assets)
    if FERRAMENTAS_DIR.exists():
        copied = 0
        for src in FERRAMENTAS_DIR.rglob("*"):
            if src.is_dir() or src.suffix == ".py" or src.name.startswith("."):
                continue
            rel = src.relative_to(PROJECT_DIR)
            dst = OUTPUT_DIR / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            copied += 1
        print(f"  Mirrored {copied} tool files to docs/ferramentas/")

    print(f"\nDone! Open: {OUTPUT_DIR.resolve()}/index.html")


if __name__ == "__main__":
    generate()
