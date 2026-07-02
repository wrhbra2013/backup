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
                    # First non-empty comment line is description
                    if not description and stripped:
                        description = stripped
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


def make_slug(name):
    """Create a URL-friendly slug from filename."""
    slug = name.replace(".sh", "").replace("_", "-")
    return slug


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
@media (max-width: 600px) { .container { padding: 12px; } th, td { padding: 6px 8px; font-size: 0.8rem; } }
"""


def render_index(scripts):
    """Render the dashboard index page."""
    dirs = {}
    for s in scripts:
        d = s["dir_name"]
        if d not in dirs:
            dirs[d] = []
        dirs[d].append(s)

    total_scripts = len(scripts)
    total_commands = sum(len([c for cat in s["commands"].values() for c in cat]) for s in scripts)
    total_functions = sum(len(s["functions"]) for s in scripts)
    total_lines = sum(s["line_count"] for s in scripts)

    rows_html = ""
    for s in scripts:
        slug = make_slug(s["filename"])
        cmd_count = sum(len(cmds) for cmds in s["commands"].values())
        func_count = len(s["functions"])

        cmd_badges = ""
        for cat, cmds in list(s["commands"].items())[:3]:
            for c in cmds[:2]:
                cmd_badges += f'<span class="badge badge-cmd">{escape(c)}</span>'
        if cmd_count > 6:
            cmd_badges += f'<span class="tag">+{cmd_count - 6} mais</span>'

        pkg_count = len(s["packages"]) + len(s["deps"])
        pkg_badge = f'<span class="badge badge-pkg">{pkg_count}</span>' if pkg_count > 0 else ""

        rows_html += f"""<tr>
  <td><a href="scripts/{slug}.html"><strong>{escape(s["filename"])}</strong></a></td>
  <td>{escape(s["description"][:80])}{'...' if len(s["description"]) > 80 else ''}</td>
  <td><span class="badge badge-dir">{s["dir_name"]}</span></td>
  <td>{cmd_badges}{pkg_badge}</td>
  <td class="cmd-count">{cmd_count} cmd · {func_count} fn · {s["line_count"]} lin</td>
  <td>
    <a href="scripts/{slug}.desktop" download class="tag" title="Download .desktop">🖥️</a>
    <a href="scripts/{slug}.html" class="tag" title="Download .sh">📄</a>
  </td>
</tr>"""

    categories_html = ""
    for d, sc in sorted(dirs.items()):
        categories_html += f'<span class="badge badge-dir">{d} ({len(sc)})</span> '

    html = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Backup Scripts — Dashboard</title>
<style>{css_style()}</style>
</head>
<body>
<div class="header-bar">
  <div class="container">
    <h1><a href="index.html">📜 Backup Scripts</a></h1>
    <div class="nav">
      <a href="index.html">Dashboard</a>
    </div>
  </div>
</div>
<div class="container">
  <h1>Dashboard de Scripts</h1>
  <p class="subtitle">Repositório público de scripts de Linux LiveCD e automação</p>

  <div class="stat-grid">
    <div class="stat-card"><div class="num">{total_scripts}</div><div class="label">Scripts</div></div>
    <div class="stat-card"><div class="num">{total_commands}</div><div class="label">Comandos</div></div>
    <div class="stat-card"><div class="num">{total_functions}</div><div class="label">Funções</div></div>
    <div class="stat-card"><div class="num">{total_lines:,}</div><div class="label">Linhas de código</div></div>
  </div>

  <p class="stat-line">Categorias: {categories_html}</p>

  <input type="text" class="search-box" id="search" placeholder="Pesquisar scripts, comandos, descrições..." oninput="filterTable()">

  <table id="script-table">
    <thead><tr><th>Script</th><th>Descrição</th><th>Diretório</th><th>Comandos / Pacotes</th><th>Info</th><th>Ações</th></tr></thead>
    <tbody>{rows_html}</tbody>
  </table>
</div>

<script>
function filterTable() {{
  var input = document.getElementById('search');
  var filter = input.value.toLowerCase();
  var rows = document.querySelectorAll('#script-table tbody tr');
  for (var i = 0; i < rows.length; i++) {{
    var text = rows[i].textContent.toLowerCase();
    rows[i].style.display = text.indexOf(filter) > -1 ? '' : 'none';
  }}
}}
</script>
</body>
</html>"""
    return html


def render_script_page(s):
    """Render individual script page."""
    slug = make_slug(s["filename"])

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

    html = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
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
<div class="container script-page">
  <a href="../index.html" class="back-link">Voltar ao Dashboard</a>

  <h1>{escape(s["filename"])}</h1>
  <p class="subtitle">{escape(s["description"])}</p>

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

    # Clean output directory
    if OUTPUT_DIR.exists():
        shutil.rmtree(OUTPUT_DIR)
    SCRIPTS_DIR.mkdir(parents=True)

    # Generate index
    print("Generating index.html...")
    index_html = render_index(scripts)
    (OUTPUT_DIR / "index.html").write_text(index_html, encoding="utf-8")

    # Generate individual pages
    for s in scripts:
        slug = make_slug(s["filename"])
        page_html = render_script_page(s)
        page_path = SCRIPTS_DIR / f"{slug}.html"
        page_path.write_text(page_html, encoding="utf-8")

        # Generate .desktop file
        desktop_content = render_desktop(s)
        desktop_path = SCRIPTS_DIR / f"{slug}.desktop"
        desktop_path.write_text(desktop_content, encoding="utf-8")

    print(f"  Generated {len(scripts)} individual pages")
    print(f"  Generated {len(scripts)} .desktop files")
    print(f"\nDone! Open: {OUTPUT_DIR.resolve()}/index.html")


if __name__ == "__main__":
    generate()
