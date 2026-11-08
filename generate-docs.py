#!/usr/bin/env python3
"""Generate static documentation site for backup project shell scripts."""

import json
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
            # Skip generated docs and .git directory
            if ".git" in path.parts:
                continue
            if OUTPUT_DIR == path or OUTPUT_DIR in path.parents:
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


def download_filename(s):
    """Name offered to the browser when downloading a script."""
    name = s["filename"]
    return name if name.endswith(".sh") else f"{name}.sh"


def download_rel_path(s):
    """Unique download path (relative to docs/scripts) preserving the source folder."""
    rel = Path(s["rel_path"])
    fname = download_filename(s)
    if len(rel.parts) == 1:
        return f"downloads/root/{fname}"
    return "downloads/" + "/".join(rel.parts[:-1]) + "/" + fname


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
.header-bar .header-cats { display: flex; align-items: center; justify-content: flex-start; gap: 12px; margin-top: 12px; padding-top: 12px; padding-bottom: 14px; border-top: 1px solid rgba(148,163,184,0.18); }
.header-cats-label { flex-shrink: 0; color: #94a3b8; font-size: 0.64rem; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; }
.cat-chips-header { flex-wrap: nowrap; margin-bottom: 0; padding-bottom: 2px; overflow-x: auto; scrollbar-width: thin; }
.cat-chips-header .cat-chip { flex: 0 0 auto; padding: 4px 10px; border-width: 1px; border-color: rgba(148,163,184,0.35); background: rgba(148,163,184,0.08); color: #cbd5e1; font-size: 0.74rem; }
.cat-chips-header .cat-chip:hover { border-color: rgba(148,163,184,0.65); background: rgba(148,163,184,0.16); color: #fff; transform: none; }
.cat-chips-header .cat-chip.active { border-color: #fff; background: #fff; color: #0f172a; }
.cat-chips-header .cat-chip .chip-count { background: rgba(148,163,184,0.2); color: #cbd5e1; }
.cat-chips-header .cat-chip.active .chip-count { background: #e2e8f0; color: #0f172a; }

.site-footer { margin-top: 48px; background: #0f172a; color: #94a3b8; }
.site-footer .container { padding-top: 30px; padding-bottom: 18px; }
.footer-grid { display: grid; grid-template-columns: minmax(0, 1.5fr) minmax(0, 1fr) auto; gap: 28px; align-items: start; }
.footer-brand strong { display: block; margin-bottom: 6px; color: #fff; font-size: 1rem; }
.footer-brand p { max-width: 480px; font-size: 0.82rem; line-height: 1.55; }
.footer-col h4 { margin-bottom: 8px; color: #e2e8f0; font-size: 0.7rem; font-weight: 700; letter-spacing: 0.12em; text-transform: uppercase; }
.footer-links { display: flex; flex-direction: column; gap: 6px; }
.footer-links a { color: #cbd5e1; font-size: 0.82rem; }
.footer-links a:hover { color: #fff; text-decoration: none; }
.footer-stats { display: flex; flex-wrap: wrap; gap: 8px; justify-content: flex-end; }
.footer-stat { min-width: 72px; padding: 8px 12px; border: 1px solid rgba(148,163,184,0.2); border-radius: 10px; background: rgba(148,163,184,0.1); text-align: center; }
.footer-stat strong { display: block; color: #fff; font-size: 1rem; line-height: 1.2; }
.footer-stat span { color: #94a3b8; font-size: 0.6rem; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; }
.footer-bottom { display: flex; justify-content: space-between; gap: 12px; flex-wrap: wrap; margin-top: 24px; padding-top: 14px; border-top: 1px solid rgba(148,163,184,0.15); font-size: 0.72rem; }
@media (max-width: 720px) { .footer-grid { grid-template-columns: 1fr; gap: 20px; } .footer-stats { justify-content: flex-start; } }
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
.actions button.tag { border: none; cursor: pointer; line-height: 1.5; }
.actions button.tag:hover { background: #d1d5db; }
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
/* ── Dashboard em carrossel de scripts ─────────────────────────── */
.dash-controls { background: #fff; border: 1px solid #e5e7eb; border-radius: 16px; padding: 16px; box-shadow: 0 1px 3px rgba(0,0,0,0.05); margin-bottom: 18px; }
.search-row { display: flex; gap: 10px; flex-wrap: wrap; align-items: center; margin-bottom: 12px; }
.search-row .search-box { flex: 1; min-width: 220px; margin-bottom: 0; }
.dash-controls .cat-chips { margin-bottom: 0; }
.dash-controls .search-row { margin-bottom: 0; }
.carousel-head { display: flex; justify-content: space-between; align-items: center; gap: 12px; flex-wrap: wrap; margin: 20px 0 10px; }
.carousel-head h2 { margin: 0; padding: 0; border: 0; }
.carousel-tools { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.carousel-tools .visible-count { font-size: 0.8rem; color: #6b7280; }
.autoplay-btn { display: inline-flex; align-items: center; gap: 6px; padding: 6px 12px; border: 1px solid #e2e8f0; border-radius: 999px; background: #fff; color: #475569; font-size: 0.75rem; font-weight: 600; cursor: pointer; transition: all 0.15s; }
.autoplay-btn:hover { border-color: #cbd5e1; background: #f8fafc; color: #0f172a; }

.photo-carousel { position: relative; background: linear-gradient(180deg, #ffffff, #f8fafc); border: 1px solid #e5e7eb; border-radius: 22px; padding: 18px; box-shadow: 0 18px 50px -30px rgba(15,23,42,0.45), 0 2px 8px rgba(0,0,0,0.05); outline: none; }
.photo-carousel:focus-visible { border-color: #93c5fd; box-shadow: 0 0 0 4px rgba(37,99,235,0.15), 0 18px 50px -30px rgba(15,23,42,0.45); }
.pc-stage { display: flex; align-items: stretch; gap: 10px; }
.pc-viewport { flex: 1; min-width: 0; overflow: hidden; border-radius: 16px; }
.pc-track { display: flex; transition: transform 0.45s cubic-bezier(0.22, 0.61, 0.36, 1); will-change: transform; }
.pc-slide { flex: 0 0 100%; min-width: 100%; padding: 2px; }
.pc-card { display: grid; grid-template-columns: minmax(0, 1.12fr) minmax(0, 1fr); min-height: 390px; background: #fff; border: 1px solid #e2e8f0; border-radius: 16px; overflow: hidden; box-shadow: 0 10px 30px -22px rgba(15,23,42,0.5); }

.pc-photo { position: relative; isolation: isolate; display: flex; flex-direction: column; justify-content: space-between; gap: 16px; min-height: 350px; padding: 24px; overflow: hidden; color: #fff; }
.pc-photo::before { content: ""; position: absolute; inset: 0; z-index: -1; background-image: linear-gradient(rgba(255,255,255,0.07) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.07) 1px, transparent 1px); background-size: 34px 34px; mask-image: radial-gradient(ellipse at 50% 45%, #000 20%, transparent 80%); }
.pc-photo::after { content: ""; position: absolute; z-index: -1; top: -130px; right: -110px; width: 340px; height: 340px; border-radius: 50%; background: rgba(255,255,255,0.14); filter: blur(1px); }
.pc-photo-top { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.pc-window { display: flex; gap: 6px; }
.pc-window i { display: block; width: 9px; height: 9px; border-radius: 50%; background: rgba(255,255,255,0.55); }
.pc-window i:nth-child(1) { background: #f87171; }
.pc-window i:nth-child(2) { background: #fbbf24; }
.pc-window i:nth-child(3) { background: #34d399; }
.pc-shell-pill { padding: 4px 10px; border: 1px solid rgba(255,255,255,0.3); border-radius: 999px; background: rgba(15,23,42,0.32); font-size: 0.64rem; font-weight: 700; letter-spacing: 0.12em; text-transform: uppercase; backdrop-filter: blur(4px); }
.pc-photo-main { display: flex; flex-direction: column; align-items: center; gap: 10px; text-align: center; }
.pc-photo-emoji { font-size: clamp(4.5rem, 9vw, 7rem); line-height: 1; filter: drop-shadow(0 12px 24px rgba(0,0,0,0.35)); }
.pc-photo-cat { font-size: 0.7rem; font-weight: 700; letter-spacing: 0.16em; text-transform: uppercase; color: rgba(255,255,255,0.85); }
.pc-photo-bottom { display: flex; flex-direction: column; gap: 4px; }
.pc-photo-file { font-family: 'Courier New', ui-monospace, monospace; font-size: 1.1rem; font-weight: 700; word-break: break-all; text-shadow: 0 2px 10px rgba(0,0,0,0.35); }
.pc-photo-meta { font-size: 0.72rem; color: rgba(255,255,255,0.82); }

.pc-info { display: flex; flex-direction: column; gap: 12px; min-width: 0; padding: 26px; }
.pc-info-top { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
.pc-size { white-space: nowrap; font-size: 0.68rem; font-weight: 600; color: #94a3b8; }
.pc-info h3 { font-family: 'Courier New', ui-monospace, monospace; font-size: 1.35rem; line-height: 1.25; color: #0f172a; word-break: break-word; }
.pc-desc { font-size: 0.9rem; line-height: 1.5; color: #475569; }
.pc-stats { display: flex; flex-wrap: wrap; gap: 6px; }
.pc-stat { padding: 4px 10px; border-radius: 999px; background: #f1f5f9; font-size: 0.72rem; color: #64748b; }
.pc-stat strong { color: #0f172a; }
.pc-pills { display: flex; flex-wrap: wrap; gap: 4px; }
.pc-pill { padding: 2px 7px; border-radius: 5px; background: #eff6ff; color: #1e40af; font-family: 'Courier New', ui-monospace, monospace; font-size: 0.68rem; }
.pc-pill.more { background: #e2e8f0; color: #475569; }
.pc-actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: auto; padding-top: 4px; }
.pc-btn { display: inline-flex; align-items: center; gap: 6px; padding: 9px 14px; border: 1px solid #e2e8f0; border-radius: 9px; background: #fff; color: #334155; font-size: 0.8rem; font-weight: 600; font-family: inherit; text-decoration: none; cursor: pointer; transition: all 0.15s; }
.pc-btn:hover { border-color: #cbd5e1; background: #f8fafc; color: #0f172a; text-decoration: none; transform: translateY(-1px); }
.pc-btn-primary { border-color: #2563eb; background: #2563eb; color: #fff; box-shadow: 0 8px 18px -10px rgba(37,99,235,0.9); }
.pc-btn-primary:hover { border-color: #1d4ed8; background: #1d4ed8; color: #fff; }
.pc-btn-ghost { background: transparent; }

.pc-arrow { display: flex; flex: 0 0 auto; align-items: center; justify-content: center; width: 48px; border: 1px solid #e2e8f0; border-radius: 14px; background: #fff; color: #334155; font-size: 1.7rem; line-height: 1; cursor: pointer; transition: all 0.15s; }
.pc-arrow:hover { border-color: #1e293b; background: #1e293b; color: #fff; }
.pc-arrow:active { transform: scale(0.97); }
.pc-progress { height: 4px; margin: 14px 2px 8px; overflow: hidden; border-radius: 999px; background: #e2e8f0; }
.pc-progress span { display: block; width: 0; height: 100%; background: linear-gradient(90deg, #2563eb, #7c3aed); transition: width 0.3s ease; }
.pc-bar { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 0 4px; }
.pc-counter { font-size: 0.75rem; font-weight: 700; letter-spacing: 0.06em; color: #2563eb; }
.pc-hint { font-size: 0.7rem; color: #94a3b8; }

.pc-thumbs { display: flex; gap: 8px; overflow-x: auto; padding: 14px 2px 8px; scroll-behavior: smooth; scrollbar-width: thin; }
.pc-thumb { display: flex; flex: 0 0 118px; flex-direction: column; gap: 4px; padding: 6px; border: 2px solid transparent; border-radius: 12px; background: transparent; font-family: inherit; text-align: left; cursor: pointer; transition: all 0.15s; }
.pc-thumb:hover { border-color: #e2e8f0; background: #f8fafc; }
.pc-thumb.active { border-color: #2563eb; background: #eff6ff; }
.pc-thumb-art { display: flex; align-items: center; justify-content: center; height: 56px; border-radius: 8px; font-size: 1.6rem; box-shadow: inset 0 0 0 1px rgba(255,255,255,0.15); }
.pc-thumb-name { overflow: hidden; color: #334155; font-family: 'Courier New', ui-monospace, monospace; font-size: 0.65rem; font-weight: 700; white-space: nowrap; text-overflow: ellipsis; }
.pc-thumb-dir { overflow: hidden; color: #94a3b8; font-size: 0.6rem; white-space: nowrap; text-overflow: ellipsis; }
.pc-empty { margin: 0 0 18px; padding: 48px 20px; border: 1px dashed #cbd5e1; border-radius: 16px; background: #fff; color: #94a3b8; font-size: 0.9rem; text-align: center; }
@media (max-width: 860px) { .pc-card { grid-template-columns: 1fr; } .pc-photo { min-height: 260px; } .pc-info { padding: 20px; } .pc-arrow { width: 40px; } }
@media (max-width: 640px) { .photo-carousel { padding: 12px; border-radius: 18px; } .pc-stage { gap: 6px; } .pc-arrow { width: 34px; border-radius: 10px; font-size: 1.3rem; } .pc-photo { min-height: 230px; padding: 18px; } .pc-info h3 { font-size: 1.15rem; } .pc-thumb { flex-basis: 96px; } .pc-hint { display: none; } }
@media (prefers-reduced-motion: reduce) { .pc-track, .pc-progress span { transition: none; } }

/* ── Carrossel de código em modal ───────────────────────────────── */
.carousel-open-btn { display: inline-flex; align-items: center; gap: 6px; padding: 8px 16px; background: #1e293b; color: #fff; border: none; border-radius: 8px; font-size: 0.82rem; font-weight: 600; cursor: pointer; transition: background 0.15s, transform 0.15s; }
.carousel-open-btn:hover { background: #334155; transform: translateY(-1px); }
body.modal-open { overflow: hidden; }
.code-modal { position: fixed; inset: 0; z-index: 1000; display: none; align-items: center; justify-content: center; padding: 16px; background: rgba(15,23,42,0.74); }
.code-modal.open { display: flex; }
.code-modal-dialog { display: flex; flex-direction: column; width: min(1120px, 100%); max-height: min(92vh, 940px); background: #0f172a; color: #e5e7eb; border-radius: 14px; overflow: hidden; box-shadow: 0 24px 70px rgba(0,0,0,0.55); animation: modalIn 0.18s ease-out; }
@keyframes modalIn { from { opacity: 0; transform: translateY(14px) scale(0.985); } to { opacity: 1; transform: none; } }
.cm-head { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; padding: 16px 20px; background: #111c33; border-bottom: 1px solid #1f2d47; }
.cm-head h3 { margin: 0; font-size: 1.05rem; color: #f8fafc; word-break: break-word; }
.cm-head .cm-sub { margin: 6px 0 0; font-size: 0.78rem; color: #94a3b8; display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.cm-head .cm-desc { color: #cbd5e1; }
.cm-close { flex-shrink: 0; width: 36px; height: 36px; border: 1px solid #334155; border-radius: 9px; background: #1e293b; color: #e2e8f0; font-size: 1rem; cursor: pointer; transition: background 0.15s, border-color 0.15s; }
.cm-close:hover { background: #dc2626; border-color: #dc2626; color: #fff; }
.cm-body { position: relative; display: flex; align-items: stretch; min-height: 0; flex: 1; }
.cm-nav { flex-shrink: 0; width: 52px; border: none; background: #0b1220; color: #93c5fd; font-size: 1.8rem; line-height: 1; cursor: pointer; transition: background 0.15s, color 0.15s; }
.cm-nav:hover { background: #1e293b; color: #fff; }
.cm-nav:disabled { opacity: 0.25; cursor: default; }
.cm-code-wrap { display: flex; flex-direction: column; flex: 1; min-width: 0; min-height: 0; }
.cm-code-meta { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 8px 16px; background: #0b1220; border-bottom: 1px solid #1f2d47; font-size: 0.72rem; color: #94a3b8; }
.cm-counter { font-weight: 700; color: #93c5fd; letter-spacing: 0.3px; }
.cm-code { flex: 1; min-height: 0; overflow: auto; padding: 12px 0; background: #0f172a; font-family: 'Courier New', ui-monospace, monospace; font-size: 0.78rem; line-height: 1.55; tab-size: 4; }
.cm-line { display: flex; white-space: pre; }
.cm-line:hover { background: rgba(148,163,184,0.08); }
.cm-ln { flex-shrink: 0; width: 52px; padding-right: 14px; text-align: right; color: #475569; user-select: none; border-right: 1px solid #1e293b; margin-right: 14px; }
.cm-lc { white-space: pre; color: #e2e8f0; }
.cm-loading { padding: 40px; text-align: center; color: #94a3b8; font-size: 0.9rem; }
.cm-foot { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; padding: 12px 20px; background: #111c33; border-top: 1px solid #1f2d47; }
.cm-btn { display: inline-flex; align-items: center; gap: 6px; padding: 8px 14px; border: 1px solid #334155; border-radius: 8px; background: #1e293b; color: #e2e8f0; font-size: 0.8rem; font-weight: 600; cursor: pointer; text-decoration: none; transition: background 0.15s, border-color 0.15s; }
.cm-btn:hover { background: #334155; border-color: #475569; text-decoration: none; color: #fff; }
.cm-btn.copied { background: #16a34a; border-color: #16a34a; }
.cm-hint { margin-left: auto; font-size: 0.7rem; color: #64748b; }
.cm-slide { animation: codeSlide 0.22s ease-out; }
@keyframes codeSlide { from { opacity: 0.3; transform: translateX(10px); } to { opacity: 1; transform: none; } }
@media (max-width: 800px) { .layout { flex-direction: column; } .sidebar { width: 100%; position: static; max-height: none; } .cat-chips { gap: 6px; } }
@media (max-width: 700px) { .code-modal { padding: 0; } .code-modal-dialog { height: 100%; max-height: 100vh; border-radius: 0; } .cm-nav { width: 40px; font-size: 1.4rem; } .cm-ln { width: 40px; padding-right: 8px; margin-right: 8px; } .cm-hint { display: none; } .cm-head { padding: 12px 14px; } .cm-foot { padding: 10px 14px; } }
"""


def render_index(scripts, cats, ferramentas=None):
    """Render the dashboard index page as a visual script carousel."""
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

    slides_html = ""
    thumbs_html = ""
    for idx, s in enumerate(scripts_sorted):
        slug = make_slug(s["filename"])
        cmd_count = sum(len(cmds) for cmds in s["commands"].values())
        func_count = len(s["functions"])
        cat = s.get("category", "config")
        clabel, cemoji, ccolor = get_category(cat)
        dir_label = DIR_SHORT.get(s["dir_name"], s["dir_name"])
        dl_rel = download_rel_path(s)
        dl_name = download_filename(s)

        desc = s["description"]
        desc_short = desc if len(desc) <= 170 else desc[:170].rstrip() + "…"

        cmds_flat = []
        for _cat, cmds in s["commands"].items():
            for c in cmds:
                if c not in cmds_flat:
                    cmds_flat.append(c)
        cmd_pills = "".join(f'<span class="pc-pill">{escape(c)}</span>' for c in cmds_flat[:6])
        if len(cmds_flat) > 6:
            cmd_pills += f'<span class="pc-pill more">+{len(cmds_flat) - 6}</span>'

        photo_bg = (
            f"background: radial-gradient(circle at 18% 18%, rgba({ccolor},0.98), transparent 58%),"
            f" radial-gradient(circle at 82% 82%, rgba({ccolor},0.55), transparent 62%),"
            f" linear-gradient(135deg, #0f172a 0%, rgba({ccolor},0.9) 100%);"
        )
        thumb_bg = f"background: radial-gradient(circle at 25% 20%, rgba({ccolor},0.95), transparent 65%), linear-gradient(135deg, #0f172a 0%, rgba({ccolor},0.85) 100%);"

        slides_html += f"""<article class="pc-slide" role="group" aria-roledescription="slide" aria-label="{escape(s["filename"])} ({escape(dir_label)})" data-cat="{cat}" data-rel="{escape(s["rel_path"])}" data-slug="{slug}" data-name="{escape(s["filename"])}" data-dir="{escape(dir_label)}" data-desc="{escape(desc_short)}" data-cat-label="{escape(clabel)}" data-cat-color="{ccolor}" data-cmd="{cmd_count}" data-fn="{func_count}" data-lines="{s["line_count"]}" data-download="{escape(dl_rel)}" data-filename="{escape(dl_name)}">
  <div class="pc-card">
    <div class="pc-photo" style="{photo_bg}">
      <div class="pc-photo-top">
        <span class="pc-window" aria-hidden="true"><i></i><i></i><i></i></span>
        <span class="pc-shell-pill">shell · .sh</span>
      </div>
      <div class="pc-photo-main">
        <span class="pc-photo-emoji" aria-hidden="true">{cemoji}</span>
        <span class="pc-photo-cat">{cemoji} {escape(clabel)}</span>
      </div>
      <div class="pc-photo-bottom">
        <span class="pc-photo-file">{escape(s["filename"])}</span>
        <span class="pc-photo-meta">{escape(dir_label)} · {cmd_count} comandos · {s["line_count"]} linhas</span>
      </div>
    </div>
    <div class="pc-info">
      <div class="pc-info-top">
        <span class="badge badge-cat" style="background:rgba({ccolor},.12);color:rgb({ccolor})">{cemoji} {escape(clabel)}</span>
        <span class="pc-size">{s["size_kb"]} KB</span>
      </div>
      <h3>{escape(s["filename"])}</h3>
      <p class="pc-desc">{escape(desc_short)}</p>
      <div class="pc-stats">
        <span class="pc-stat"><strong>{cmd_count}</strong> comandos</span>
        <span class="pc-stat"><strong>{func_count}</strong> funções</span>
        <span class="pc-stat"><strong>{s["line_count"]}</strong> linhas</span>
      </div>
      <div class="pc-pills">{cmd_pills}</div>
      <div class="pc-actions">
        <a class="pc-btn pc-btn-primary" href="scripts/{escape(dl_rel)}" download="{escape(dl_name)}">⬇️ Baixar .sh</a>
        <button type="button" class="pc-btn code-open" data-rel="{escape(s["rel_path"])}">📖 Ver código</button>
        <a class="pc-btn" href="scripts/{slug}.html">📄 Detalhes</a>
        <a class="pc-btn pc-btn-ghost" href="scripts/{slug}.desktop" download>🖥️ .desktop</a>
      </div>
    </div>
  </div>
</article>"""

        thumbs_html += f"""<button type="button" class="pc-thumb" data-cat="{cat}" data-rel="{escape(s["rel_path"])}" data-slug="{slug}" title="{escape(s["filename"])} — {escape(dir_label)}">
  <span class="pc-thumb-art" style="{thumb_bg}">{cemoji}</span>
  <span class="pc-thumb-name">{escape(s["filename"])}</span>
  <span class="pc-thumb-dir">{escape(dir_label)}</span>
</button>"""

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

    html = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'unsafe-inline' file:; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; connect-src 'self' https://api.github.com https://raw.githubusercontent.com;">
<link rel="icon" href="/favicon.ico" sizes="any">
<title>Backup Scripts — Galeria de Scripts</title>
<style>{css_style()}</style>
</head>
<body id="top">
<div class="header-bar">
  <div class="container">
    <h1><a href="index.html">📜 Backup Scripts</a></h1>
    <div class="nav">
      <a href="index.html" class="active">Dashboard</a>
      <a href="https://github.com/wrhbra2013/backup" target="_blank" rel="noopener">GitHub</a>
    </div>
  </div>
  <div class="container header-cats">
    <span class="header-cats-label">Categorias</span>
    <div class="cat-chips cat-chips-header">{chips_html}</div>
  </div>
</div>
<div class="container">
  <h1>Dashboard de Scripts</h1>
  <p class="subtitle">Galeria visual de scripts de Linux, LiveCD, automação e ferramentas — navegue pelas capas e baixe o <code>.sh</code> direto.</p>

  <div class="stat-grid">
    <div class="stat-card"><div class="num">{total_scripts}</div><div class="label">Scripts</div></div>
    <div class="stat-card"><div class="num">{total_categories}</div><div class="label">Categorias</div></div>
    <div class="stat-card"><div class="num">{total_commands}</div><div class="label">Comandos</div></div>
    <div class="stat-card"><div class="num">{total_functions}</div><div class="label">Funções</div></div>
    <div class="stat-card"><div class="num">{total_lines:,}</div><div class="label">Linhas de código</div></div>
  </div>

  <div class="dash-controls">
    <div class="search-row">
      <input type="text" class="search-box" id="search" placeholder="Pesquisar por script, categoria, descrição ou comando..." oninput="applyFilters()">
      <button type="button" class="carousel-open-btn" id="open-carousel" title="Abrir o script atual no leitor de código">🎬 Modo código</button>
    </div>
  </div>

  <div class="carousel-head">
    <h2>🎞️ Carrossel de scripts</h2>
    <div class="carousel-tools">
      <span class="visible-count" id="visible-count">{total_scripts} de {total_scripts} scripts</span>
      <button type="button" class="autoplay-btn" id="pc-autoplay" aria-pressed="true" title="Pausar ou retomar a troca automática">⏸ Pausar</button>
    </div>
  </div>

  <section class="photo-carousel" id="script-carousel" tabindex="0" aria-roledescription="carrossel" aria-label="Carrossel de scripts">
    <div class="pc-stage">
      <button type="button" class="pc-arrow" id="pc-prev" aria-label="Script anterior">‹</button>
      <div class="pc-viewport" id="pc-viewport">
        <div class="pc-track" id="pc-track">{slides_html}</div>
      </div>
      <button type="button" class="pc-arrow" id="pc-next" aria-label="Próximo script">›</button>
    </div>
    <div class="pc-progress" aria-hidden="true"><span id="pc-progress-bar"></span></div>
    <div class="pc-bar">
      <span class="pc-counter" id="pc-counter">1 / {total_scripts}</span>
      <span class="pc-hint">Use ← →, arraste ou clique nas miniaturas</span>
    </div>
  </section>

  <div class="pc-empty" id="pc-empty" style="display:none">Nenhum script encontrado. Ajuste a busca ou o filtro de categoria.</div>

  <div class="pc-thumbs" id="pc-thumbs" aria-label="Miniaturas dos scripts">{thumbs_html}</div>

  {'<h2 style="margin-top:2rem">🧰 Ferramentas HTML</h2><div class="tool-grid">' + ferramentas_cards + '</div>' if ferramentas_cards else ''}
</div>

<footer class="site-footer">
  <div class="container">
    <div class="footer-grid">
      <div class="footer-brand">
        <strong>📜 Backup Scripts</strong>
        <p>Repositório de scripts de Linux, LiveCD, automação, empacotamento e ferramentas de sistema. Baixe os arquivos <code>.sh</code> diretamente pelo carrossel.</p>
      </div>
      <div class="footer-col">
        <h4>Navegação</h4>
        <div class="footer-links">
          <a href="index.html">Dashboard</a>
          <a href="https://github.com/wrhbra2013/backup" target="_blank" rel="noopener">Repositório no GitHub</a>
          <a href="#top">Voltar ao topo ↑</a>
        </div>
      </div>
      <div class="footer-col">
        <h4>Resumo</h4>
        <div class="footer-stats">
          <div class="footer-stat"><strong>{total_scripts}</strong><span>scripts</span></div>
          <div class="footer-stat"><strong>{total_categories}</strong><span>categorias</span></div>
          <div class="footer-stat"><strong>{total_lines:,}</strong><span>linhas</span></div>
        </div>
      </div>
    </div>
    <div class="footer-bottom">
      <span>Backup Scripts — documentação gerada automaticamente.</span>
      <span>Shell Script · Linux · LiveCD · Automação</span>
    </div>
  </div>
</footer>

<div class="code-modal" id="code-modal" role="dialog" aria-modal="true" aria-labelledby="cm-title">
  <div class="code-modal-dialog">
    <div class="cm-head">
      <div>
        <h3 id="cm-title">Script</h3>
        <div class="cm-sub">
          <span class="badge badge-cat" id="cm-cat"></span>
          <span class="cm-desc" id="cm-desc"></span>
          <span id="cm-stats"></span>
        </div>
      </div>
      <button type="button" class="cm-close" id="cm-close" aria-label="Fechar (Esc)">✕</button>
    </div>
    <div class="cm-body">
      <button type="button" class="cm-nav" id="cm-prev" aria-label="Script anterior (←)">‹</button>
      <div class="cm-code-wrap">
        <div class="cm-code-meta">
          <span class="cm-counter" id="cm-counter">0 / 0</span>
          <span id="cm-file"></span>
        </div>
        <div class="cm-code" id="cm-code" tabindex="0"></div>
      </div>
      <button type="button" class="cm-nav" id="cm-next" aria-label="Próximo script (→)">›</button>
    </div>
    <div class="cm-foot">
      <button type="button" class="cm-btn" id="cm-copy">📋 Copiar</button>
      <a class="cm-btn" id="cm-download" href="#" download>💾 Baixar .sh</a>
      <a class="cm-btn" id="cm-page" href="#">📄 Página completa</a>
      <a class="cm-btn" id="cm-desktop" href="#" download>🖥️ .desktop</a>
      <span class="cm-hint">← → navegar · Esc fechar</span>
    </div>
  </div>
</div>

<script>
var currentCat = '';
var pcIndex = 0;
var sourceCache = null;
var sourcesLoading = false;
var pendingSources = null;
var lastFocus = null;
var carouselItems = [];
var carouselIndex = 0;
var autoplayEnabled = !(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
var autoplayTimer = null;
var autoplayPaused = false;

function allSlides() {{
  return Array.prototype.slice.call(document.querySelectorAll('#pc-track .pc-slide'));
}}
function visibleSlides() {{
  return allSlides().filter(function (s) {{ return s.style.display !== 'none'; }});
}}
function setCategory(cat) {{
  currentCat = (currentCat === cat) ? '' : cat;
  var chips = document.querySelectorAll('.cat-chip');
  for (var i = 0; i < chips.length; i++) {{
    chips[i].classList.toggle('active', chips[i].getAttribute('data-cat') === currentCat);
  }}
  applyFilters();
}}
function applyFilters() {{
  var term = (document.getElementById('search').value || '').toLowerCase().trim();
  var slides = allSlides();
  var thumbs = document.querySelectorAll('#pc-thumbs .pc-thumb');
  var visible = 0;
  for (var i = 0; i < slides.length; i++) {{
    var slide = slides[i];
    var text = (slide.textContent || '').toLowerCase();
    var matchTerm = !term || text.indexOf(term) !== -1;
    var matchCat = !currentCat || slide.getAttribute('data-cat') === currentCat;
    var show = matchTerm && matchCat;
    slide.style.display = show ? '' : 'none';
    if (show) visible++;
  }}
  for (var j = 0; j < thumbs.length; j++) {{
    var thumb = thumbs[j];
    var ttext = (thumb.textContent || '').toLowerCase();
    var tm = !term || ttext.indexOf(term) !== -1;
    var tc = !currentCat || thumb.getAttribute('data-cat') === currentCat;
    thumb.style.display = (tm && tc) ? '' : 'none';
  }}
  pcIndex = 0;
  updateCarousel(false);
  var count = document.getElementById('visible-count');
  if (count) count.textContent = visible + ' de ' + slides.length + ' scripts';
  document.getElementById('pc-empty').style.display = visible ? 'none' : '';
  document.getElementById('script-carousel').style.display = visible ? '' : 'none';
  document.getElementById('pc-thumbs').style.display = visible ? '' : 'none';
}}
function updateCarousel(animate) {{
  var vis = visibleSlides();
  var track = document.getElementById('pc-track');
  if (!vis.length) {{ track.style.transform = 'translateX(0)'; return; }}
  if (pcIndex < 0) pcIndex = 0;
  if (pcIndex >= vis.length) pcIndex = 0;
  if (animate === false) track.style.transition = 'none';
  track.style.transform = 'translateX(' + (-pcIndex * 100) + '%)';
  if (animate === false) {{ void track.offsetWidth; track.style.transition = ''; }}
  var counter = document.getElementById('pc-counter');
  if (counter) counter.textContent = (pcIndex + 1) + ' / ' + vis.length;
  var bar = document.getElementById('pc-progress-bar');
  if (bar) bar.style.width = (((pcIndex + 1) / vis.length) * 100) + '%';
  var all = allSlides();
  for (var i = 0; i < all.length; i++) {{
    var current = all[i] === vis[pcIndex];
    all[i].setAttribute('aria-hidden', current ? 'false' : 'true');
  }}
  var rel = vis[pcIndex].getAttribute('data-rel');
  var thumbs = document.querySelectorAll('#pc-thumbs .pc-thumb');
  for (var j = 0; j < thumbs.length; j++) {{
    var active = thumbs[j].getAttribute('data-rel') === rel;
    thumbs[j].classList.toggle('active', active);
    if (active && animate !== false) {{
      var strip = document.getElementById('pc-thumbs');
      var left = thumbs[j].offsetLeft - strip.clientWidth / 2 + thumbs[j].clientWidth / 2;
      if (strip.scrollTo) strip.scrollTo({{ left: left, behavior: 'smooth' }});
    }}
  }}
}}
function moveCarousel(step) {{
  var vis = visibleSlides();
  if (!vis.length) return;
  pcIndex = (pcIndex + step + vis.length) % vis.length;
  updateCarousel(true);
}}
function goToSlideByRel(rel) {{
  var vis = visibleSlides();
  for (var i = 0; i < vis.length; i++) {{
    if (vis[i].getAttribute('data-rel') === rel) {{ pcIndex = i; updateCarousel(true); return; }}
  }}
}}
function startAutoplay() {{
  stopAutoplay();
  if (!autoplayEnabled) return;
  autoplayTimer = setInterval(function () {{
    if (document.hidden || autoplayPaused || document.body.classList.contains('modal-open')) return;
    moveCarousel(1);
  }}, 6500);
}}
function stopAutoplay() {{
  if (autoplayTimer) {{ clearInterval(autoplayTimer); autoplayTimer = null; }}
}}
function setAutoplay(on) {{
  autoplayEnabled = on;
  var btn = document.getElementById('pc-autoplay');
  if (btn) {{
    btn.textContent = on ? '⏸ Pausar' : '▶ Reproduzir';
    btn.setAttribute('aria-pressed', on ? 'true' : 'false');
  }}
  if (on) startAutoplay(); else stopAutoplay();
}}

function ensureSources(cb) {{
  if (sourceCache) {{ cb(sourceCache); return; }}
  pendingSources = cb;
  if (sourcesLoading) return;
  sourcesLoading = true;
  var s = document.createElement('script');
  s.src = 'scripts/sources.js';
  s.onload = function () {{
    sourcesLoading = false;
    sourceCache = window.__SCRIPT_SOURCES || {{}};
    if (pendingSources) {{ var f = pendingSources; pendingSources = null; f(sourceCache); }}
  }};
  s.onerror = function () {{
    sourcesLoading = false;
    sourceCache = {{}};
    if (pendingSources) {{ var f = pendingSources; pendingSources = null; f(sourceCache); }}
  }};
  document.head.appendChild(s);
}}

function slideToItem(slide) {{
  return {{
    rel: slide.getAttribute('data-rel') || '',
    slug: slide.getAttribute('data-slug'),
    name: slide.getAttribute('data-name'),
    desc: slide.getAttribute('data-desc') || '',
    cat: slide.getAttribute('data-cat-label') || '',
    catColor: slide.getAttribute('data-cat-color') || '148,163,184',
    dir: slide.getAttribute('data-dir') || '',
    cmd: slide.getAttribute('data-cmd') || '0',
    fn: slide.getAttribute('data-fn') || '0',
    lines: slide.getAttribute('data-lines') || '0',
    download: slide.getAttribute('data-download') || '',
    filename: slide.getAttribute('data-filename') || slide.getAttribute('data-name')
  }};
}}

function openCarousel(index) {{
  var slides = visibleSlides();
  if (!slides.length) return;
  carouselItems = slides.map(slideToItem);
  if (typeof index !== 'number' || index < 0) index = 0;
  if (index >= carouselItems.length) index = 0;
  carouselIndex = index;
  lastFocus = document.activeElement;
  document.getElementById('code-modal').classList.add('open');
  document.body.classList.add('modal-open');
  renderCarouselItem();
  document.getElementById('cm-close').focus();
}}

function closeCarousel() {{
  document.getElementById('code-modal').classList.remove('open');
  document.body.classList.remove('modal-open');
  if (lastFocus && lastFocus.focus) lastFocus.focus();
}}

function moveModal(step) {{
  if (!carouselItems.length) return;
  carouselIndex = (carouselIndex + step + carouselItems.length) % carouselItems.length;
  renderCarouselItem();
}}

function renderCarouselItem() {{
  var item = carouselItems[carouselIndex];
  if (!item) return;
  document.getElementById('cm-title').textContent = item.name + (item.dir ? ' (' + item.dir + ')' : '');
  document.getElementById('cm-counter').textContent = (carouselIndex + 1) + ' / ' + carouselItems.length;
  document.getElementById('cm-file').textContent = item.name;
  document.getElementById('cm-desc').textContent = item.desc;
  var badge = document.getElementById('cm-cat');
  badge.textContent = item.cat;
  badge.style.background = 'rgba(' + item.catColor + ',0.16)';
  badge.style.color = 'rgb(' + item.catColor + ')';
  document.getElementById('cm-stats').textContent = item.cmd + ' cmd · ' + item.fn + ' fn · ' + item.lines + ' lin';
  document.getElementById('cm-page').href = 'scripts/' + item.slug + '.html';
  document.getElementById('cm-desktop').href = 'scripts/' + item.slug + '.desktop';
  var dl = document.getElementById('cm-download');
  dl.href = 'scripts/' + item.download;
  dl.download = item.filename;

  var code = document.getElementById('cm-code');
  code.innerHTML = '<div class="cm-loading">Carregando código…</div>';
  code.scrollTop = 0;
  ensureSources(function (src) {{
    var now = carouselItems[carouselIndex];
    if (!now || now.rel !== item.rel) return;
    var text = src[item.rel];
    if (typeof text !== 'string') text = src[item.slug];
    if (typeof text !== 'string') {{
      code.textContent = '';
      var msg = document.createElement('div');
      msg.className = 'cm-loading';
      msg.appendChild(document.createTextNode('Código não disponível. '));
      var a = document.createElement('a');
      a.href = 'scripts/' + item.slug + '.html';
      a.textContent = 'Abrir página completa';
      a.style.color = '#93c5fd';
      msg.appendChild(a);
      code.appendChild(msg);
      return;
    }}
    renderSource(text);
  }});
}}

function renderSource(text) {{
  var code = document.getElementById('cm-code');
  var lines = text.replace(/\\r\\n/g, '\\n').replace(/\\n$/, '').split('\\n');
  var frag = document.createDocumentFragment();
  for (var i = 0; i < lines.length; i++) {{
    var row = document.createElement('div');
    row.className = 'cm-line';
    var ln = document.createElement('span');
    ln.className = 'cm-ln';
    ln.textContent = i + 1;
    var lc = document.createElement('span');
    lc.className = 'cm-lc';
    lc.textContent = lines[i] || ' ';
    row.appendChild(ln);
    row.appendChild(lc);
    frag.appendChild(row);
  }}
  code.textContent = '';
  code.appendChild(frag);
  code.classList.remove('cm-slide');
  void code.offsetWidth;
  code.classList.add('cm-slide');
}}

function currentSource() {{
  var item = carouselItems[carouselIndex];
  if (!item || !sourceCache) return null;
  return sourceCache[item.rel] || sourceCache[item.slug] || null;
}}

function fallbackCopy(text, done) {{
  var ta = document.createElement('textarea');
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  document.body.appendChild(ta);
  ta.select();
  try {{ document.execCommand('copy'); }} catch (e) {{}}
  document.body.removeChild(ta);
  done();
}}

function copyCurrent() {{
  var text = currentSource();
  if (typeof text !== 'string') return;
  var done = function () {{
    var btn = document.getElementById('cm-copy');
    btn.textContent = '✅ Copiado!';
    btn.classList.add('copied');
    setTimeout(function () {{ btn.textContent = '📋 Copiar'; btn.classList.remove('copied'); }}, 2000);
  }};
  if (navigator.clipboard && navigator.clipboard.writeText) {{
    navigator.clipboard.writeText(text).then(done).catch(function () {{ fallbackCopy(text, done); }});
  }} else {{
    fallbackCopy(text, done);
  }}
}}

document.addEventListener('click', function (e) {{
  var codeBtn = e.target.closest ? e.target.closest('.code-open') : null;
  if (codeBtn) {{
    e.preventDefault();
    var rel = codeBtn.getAttribute('data-rel');
    var slides = visibleSlides();
    var idx = -1;
    for (var i = 0; i < slides.length; i++) {{
      if (slides[i].getAttribute('data-rel') === rel) {{ idx = i; break; }}
    }}
    openCarousel(idx >= 0 ? idx : pcIndex);
    return;
  }}
  if (e.target && e.target.id === 'open-carousel') {{ openCarousel(pcIndex); return; }}
  if (e.target && e.target.id === 'code-modal') {{ closeCarousel(); }}
}});

document.getElementById('pc-prev').addEventListener('click', function () {{ moveCarousel(-1); }});
document.getElementById('pc-next').addEventListener('click', function () {{ moveCarousel(1); }});
document.getElementById('pc-autoplay').addEventListener('click', function () {{ setAutoplay(!autoplayEnabled); }});
document.getElementById('pc-thumbs').addEventListener('click', function (e) {{
  var thumb = e.target.closest ? e.target.closest('.pc-thumb') : null;
  if (thumb) goToSlideByRel(thumb.getAttribute('data-rel'));
}});

var scriptCarousel = document.getElementById('script-carousel');
scriptCarousel.addEventListener('keydown', function (e) {{
  if (e.key === 'ArrowLeft') {{ e.preventDefault(); moveCarousel(-1); }}
  else if (e.key === 'ArrowRight') {{ e.preventDefault(); moveCarousel(1); }}
}});
scriptCarousel.addEventListener('mouseenter', function () {{ autoplayPaused = true; }});
scriptCarousel.addEventListener('mouseleave', function () {{ autoplayPaused = false; }});
scriptCarousel.addEventListener('focusin', function () {{ autoplayPaused = true; }});
scriptCarousel.addEventListener('focusout', function () {{ autoplayPaused = false; }});

document.getElementById('cm-close').addEventListener('click', closeCarousel);
document.getElementById('cm-prev').addEventListener('click', function () {{ moveModal(-1); }});
document.getElementById('cm-next').addEventListener('click', function () {{ moveModal(1); }});
document.getElementById('cm-copy').addEventListener('click', copyCurrent);

document.addEventListener('keydown', function (e) {{
  var modal = document.getElementById('code-modal');
  if (!modal.classList.contains('open')) return;
  if (e.key === 'Escape') {{ closeCarousel(); }}
  else if (e.key === 'ArrowLeft') {{ e.preventDefault(); moveModal(-1); }}
  else if (e.key === 'ArrowRight') {{ e.preventDefault(); moveModal(1); }}
}});

(function () {{
  var vp = document.getElementById('pc-viewport');
  var startX = null, startY = null;
  vp.addEventListener('touchstart', function (e) {{
    if (e.touches.length !== 1) return;
    startX = e.touches[0].clientX;
    startY = e.touches[0].clientY;
  }}, {{ passive: true }});
  vp.addEventListener('touchend', function (e) {{
    if (startX === null) return;
    var dx = e.changedTouches[0].clientX - startX;
    var dy = e.changedTouches[0].clientY - startY;
    startX = null; startY = null;
    if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5) {{
      moveCarousel(dx < 0 ? 1 : -1);
    }}
  }}, {{ passive: true }});
}})();

applyFilters();
if (!autoplayEnabled) {{
  document.getElementById('pc-autoplay').textContent = '▶ Reproduzir';
  document.getElementById('pc-autoplay').setAttribute('aria-pressed', 'false');
}}
startAutoplay();
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
<meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'unsafe-inline' file:; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:;">
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
          <a href="{escape(s["download_rel"])}" download="{escape(download_filename(s))}" class="copy-btn" id="dl-btn">💾 Download .sh</a>
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
        s["download_rel"] = download_rel_path(s)
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

        # Generate a real .sh download preserving the source folder (avoids duplicate names)
        download_path = SCRIPTS_DIR / s["download_rel"]
        download_path.parent.mkdir(parents=True, exist_ok=True)
        download_path.write_text(s["content"], encoding="utf-8")
        os.chmod(download_path, 0o755)

    print(f"  Generated {len(scripts)} individual pages")
    print(f"  Generated {len(scripts)} .desktop files")
    print(f"  Generated {len(scripts)} downloadable .sh files")

    # Bundle all sources for the dashboard's code carousel (lazy-loaded by index.html)
    print("Generating source bundle for carousel...")
    sources = {}
    for s in scripts:
        # Key by relative path so same-named scripts in different folders keep their own source.
        sources[s["rel_path"]] = s["content"]
    sources_js = "window.__SCRIPT_SOURCES = " + json.dumps(sources, ensure_ascii=True) + ";\n"
    (SCRIPTS_DIR / "sources.js").write_text(sources_js, encoding="utf-8")
    print(f"  Generated scripts/sources.js ({len(sources)} entries)")

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
