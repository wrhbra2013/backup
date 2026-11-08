#!/bin/bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 <AppImage> [options]

Convert an AppImage to an RPM package for Oracle Linux / RHEL 9.

Options:
  -o <dir>    Output directory for the RPM (default: current dir)
  -n <name>   Package name (default: derived from AppImage filename)
  -v <ver>    Package version (default: derived from AppImage filename)
  -h          Show this help

Example:
  $0 foo-1.2.3-x86_64.AppImage
EOF
  exit 1
}

OUTDIR="."
PACKAGE_NAME=""
PACKAGE_VER=""

while getopts "o:n:v:h" opt; do
  case "$opt" in
    o) OUTDIR="$OPTARG" ;;
    n) PACKAGE_NAME="$OPTARG" ;;
    v) PACKAGE_VER="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

shift $((OPTIND-1))
[ $# -lt 1 ] && usage

APPIMAGE="$1"
[ ! -f "$APPIMAGE" ] && echo "Error: file not found: $APPIMAGE" && exit 1
[ ! -x "$APPIMAGE" ] && echo "Error: file not executable: $APPIMAGE" && exit 1

BASENAME=$(basename "$APPIMAGE")
BASENAME_NOEXT="${BASENAME%.AppImage}"

# Derive name + version from filename if not provided
if [ -z "$PACKAGE_NAME" ] || [ -z "$PACKAGE_VER" ]; then
  IFS='-' read -ra PARTS <<< "$BASENAME_NOEXT"
  if [ ${#PARTS[@]} -ge 3 ]; then
    CANDIDATE_VER="${PARTS[-2]}-${PARTS[-1]}"
    CANDIDATE_VER="${CANDIDATE_VER#v}"
    CANDIDATE_NAME=""
    for ((i=0; i<${#PARTS[@]}-2; i++)); do
      [ -n "$CANDIDATE_NAME" ] && CANDIDATE_NAME+="-"
      CANDIDATE_NAME+="${PARTS[$i]}"
    done
    if [ -z "$PACKAGE_NAME" ]; then PACKAGE_NAME="$CANDIDATE_NAME"; fi
    if [ -z "$PACKAGE_VER" ]; then PACKAGE_VER="$CANDIDATE_VER"; fi
  else
    [ -z "$PACKAGE_NAME" ] && PACKAGE_NAME="$BASENAME_NOEXT"
    [ -z "$PACKAGE_VER" ] && PACKAGE_VER="1.0.0"
  fi
fi

# Sanitize version for RPM (no hyphens)
PACKAGE_VER="${PACKAGE_VER//-/_}"

WORKDIR=$(mktemp -d)
trap "rm -rf '$WORKDIR'" EXIT

echo "=== Extracting AppImage ==="
cd "$WORKDIR"
"$APPIMAGE" --appimage-extract >/dev/null 2>&1
cd squashfs-root

echo "=== Analyzing structure ==="

APPNAME="$PACKAGE_NAME"
WRAPPER_SCRIPT=""

# Find the main binary / wrapper
if [ -f "AppRun" ]; then
  WRAPPER_SCRIPT="AppRun"
elif [ -f "apprun" ]; then
  WRAPPER_SCRIPT="apprun"
else
  WRAPPER_SCRIPT=$(find . -maxdepth 2 -type f -name "*.sh" -o -name "*-wrapper" -o -name "wrapper" | head -1)
  WRAPPER_SCRIPT="${WRAPPER_SCRIPT#./}"
fi

[ -z "$WRAPPER_SCRIPT" ] && echo "Error: no AppRun/wrapper found" && exit 1

# Determine the main binary directory
BIN_DIR=""
WRAPPER_DIR=$(dirname "$WRAPPER_SCRIPT")
if [ "$WRAPPER_DIR" = "." ]; then
  # Check if usr/bin/ or opt/ has the real binary
  if [ -d "opt/$APPNAME" ]; then
    BIN_DIR="opt/$APPNAME"
  elif [ -d "usr/lib/$APPNAME" ]; then
    BIN_DIR="usr/lib/$APPNAME"
  elif [ -d "usr/lib64/$APPNAME" ]; then
    BIN_DIR="usr/lib64/$APPNAME"
  else
    BIN_DIR="opt/$APPNAME"
  fi
else
  BIN_DIR="$WRAPPER_DIR"
fi
BIN_DIR="${BIN_DIR#./}"

# Make sure we're using the subdirectory, not "."
if [ "$BIN_DIR" = "." ]; then
  mkdir -p "opt/$APPNAME"
  find . -maxdepth 1 -type f | while read f; do
    [ "$(basename "$f")" != ".DirIcon" ] && mv "$f" "opt/$APPNAME/"
  done
  cp -a usr "opt/$APPNAME/" 2>/dev/null || true
  BIN_DIR="opt/$APPNAME"
fi

echo "  Binary dir: $BIN_DIR"
echo "  Wrapper: $WRAPPER_SCRIPT"

# Desktop file
DESKTOP_FILE=$(find . -maxdepth 2 -name "*.desktop" | head -1)
[ -z "$DESKTOP_FILE" ] && echo "Error: no .desktop file found" && exit 1
DESKTOP_FILE="${DESKTOP_FILE#./}"
echo "  Desktop file: $DESKTOP_FILE"

# Icon
ICON_FILE=""
for icon in "${APPNAME}.png" "${APPNAME}.svg" "icon.png" "icon.svg"; do
  [ -f "$icon" ] && ICON_FILE="$icon" && break
done
# Try to find it from the desktop file
if [ -z "$ICON_FILE" ]; then
  ICON_NAME=$(grep -i '^Icon=' "$DESKTOP_FILE" | head -1 | cut -d= -f2)
  [ -n "$ICON_NAME" ] && for ext in png svg; do
    found=$(find . -name "${ICON_NAME}.${ext}" -maxdepth 2 | head -1)
    [ -n "$found" ] && ICON_FILE="${found#./}" && break
  done
fi
# Last resort: find any png
[ -z "$ICON_FILE" ] && ICON_FILE=$(find . -maxdepth 2 -name "*.png" | head -1)
[ -z "$ICON_FILE" ] && ICON_FILE=$(find usr/share/icons -name "*.png" | head -1)
ICON_FILE="${ICON_FILE#./}"
echo "  Icon: $ICON_FILE"

# Determine License from desktop file
LICENSE=$(grep -i '^X-AppImage-License=' "$DESKTOP_FILE" 2>/dev/null | cut -d= -f2) || true
[ -z "$LICENSE" ] && LICENSE="Proprietary"

# Determine Summary from desktop file
SUMMARY=$(grep -i '^Comment=' "$DESKTOP_FILE" 2>/dev/null | head -1 | cut -d= -f2) || true
[ -z "$SUMMARY" ] && SUMMARY="$APPNAME"
SUMMARY="${SUMMARY:0:80}"

# Determine URL
URL=$(grep -i '^URL=' "$DESKTOP_FILE" 2>/dev/null | head -1 | cut -d= -f2) || true
[ -z "$URL" ] && URL="https://$APPNAME.org"

# Check for Libraries
HAS_LIBS="false"
if ls "$BIN_DIR"/*.so* >/dev/null 2>&1; then
  HAS_LIBS="true"
fi

# Check for locales
HAS_LOCALES="false"
[ -d "$BIN_DIR/locales" ] && HAS_LOCALES="true"

# Detect wrapper name for the symlink
WRAPPER_IN_BIN=$(basename "$WRAPPER_SCRIPT")
# But what's the actual executable inside BIN_DIR?
LAUNCHER_IN_BIN=$(find "$BIN_DIR" -maxdepth 1 -type f -executable ! -name "*.so*" ! -name "*.pak" ! -name "*.dat" ! -name "*.json" | head -1)
LAUNCHER_NAME=$(basename "$LAUNCHER_IN_BIN" 2>/dev/null || echo "$APPNAME")

# Do we need to fix the desktop Exec line?
DESKTOP_EXEC=$(grep '^Exec=' "$DESKTOP_FILE" 2>/dev/null | head -1 | cut -d= -f2 | cut -d' ' -f1)
DESKTOP_EXEC=$(basename "$DESKTOP_EXEC" 2>/dev/null || echo "$WRAPPER_IN_BIN")

# Post-install ldconfig needed only if there are .so files
POST_LDCONFIG=""
[ "$HAS_LIBS" = "true" ] && POST_LDCONFIG='/sbin/ldconfig 2>/dev/null || :'

echo
echo "=== Creating spec file ==="

SPECFILE="$WORKDIR/$APPNAME.spec"
mkdir -p "$HOME/rpmbuild/SPECS" "$HOME/rpmbuild/SOURCES"

cat > "$SPECFILE" << SPECEOF
%define app_prefix /opt/${APPNAME}
%define debug_package %{nil}

Name:           ${APPNAME}
Version:        ${PACKAGE_VER}
Release:        1%{?dist}
Summary:        ${SUMMARY}

License:        ${LICENSE}
URL:            ${URL}
Source0:        ${APPNAME}-${PACKAGE_VER}.tar.gz

BuildArch:      x86_64
BuildRequires:  desktop-file-utils

Requires:       fontconfig, freetype, glib2
Requires:       libX11, libXcomposite, libXcursor, libXdamage
Requires:       libXext, libXfixes, libXi, libXrandr
Requires:       libXrender, libXtst, libXScrnSaver
Requires:       libdrm, libxcb, nss, nspr
Requires:       alsa-lib, cups-libs
Requires:       atk, at-spi2-atk, at-spi2-core
Requires:       pango, cairo, gtk3, gdk-pixbuf2
Requires:       libgbm, libxkbcommon, mesa-libEGL
Requires:       bzip2-libs, systemd-libs

%description
${SUMMARY}

%prep
%setup -q

%build

%install
rm -rf %{buildroot}

install -d %{buildroot}%{app_prefix}
cp -a ${BIN_DIR}/* %{buildroot}%{app_prefix}/

install -d %{buildroot}%{_datadir}/applications
desktop-file-install --dir=%{buildroot}%{_datadir}/applications \
  --set-key=Exec --set-value="%{app_prefix}/${LAUNCHER_NAME} %%U" \
  --set-key=Icon --set-value=${APPNAME} \
  ${DESKTOP_FILE}

install -d %{buildroot}%{_bindir}
ln -sf %{app_prefix}/${LAUNCHER_NAME} %{buildroot}%{_bindir}/${APPNAME}

install -d %{buildroot}%{_datadir}/icons/hicolor

if [ -f "${ICON_FILE}" ]; then
  for size in 16 22 24 32 48 64 128 256; do
    sizedir=%{buildroot}%{_datadir}/icons/hicolor/\${size}x\${size}/apps
    install -d "\$sizedir"
    install -m644 ${ICON_FILE} "\$sizedir/${APPNAME}.png"
  done
  install -d %{buildroot}%{_datadir}/icons/hicolor/scalable/apps
  install -m644 ${ICON_FILE} %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/${APPNAME}.png
fi

%files
%defattr(-,root,root,-)
%{app_prefix}/
%{_bindir}/${APPNAME}
%{_datadir}/applications/${APPNAME}.desktop
%{_datadir}/icons/hicolor/*/apps/${APPNAME}.png

%post
${POST_LDCONFIG}
gtk-update-icon-cache %{_datadir}/icons/hicolor 2>/dev/null || :

%postun
${POST_LDCONFIG}
gtk-update-icon-cache %{_datadir}/icons/hicolor 2>/dev/null || :

%changelog
* $(date "+%a %b %d %Y") - ${APPNAME} ${PACKAGE_VER}-1
- Initial RPM build from AppImage
SPECEOF

echo "=== Creating source tarball ==="

cd "$WORKDIR"
# Remove the squashfs-root symlink
rm -f squashfs-root/.DirIcon 2>/dev/null || true
mv squashfs-root "${APPNAME}-${PACKAGE_VER}"
tar czf "$HOME/rpmbuild/SOURCES/${APPNAME}-${PACKAGE_VER}.tar.gz" "${APPNAME}-${PACKAGE_VER}"

echo "=== Building RPM ==="
cp "$SPECFILE" "$HOME/rpmbuild/SPECS/"
rpmbuild -bb "$HOME/rpmbuild/SPECS/${APPNAME}.spec"

echo
echo "=== Done ==="
RPMFILE="$HOME/rpmbuild/RPMS/x86_64/${APPNAME}-${PACKAGE_VER}-1.el9.x86_64.rpm"
if [ -f "$RPMFILE" ]; then
  mkdir -p "$OUTDIR"
  cp "$RPMFILE" "$OUTDIR/"
  echo "RPM created: $OUTDIR/$(basename $RPMFILE)"
  ls -lh "$OUTDIR/$(basename $RPMFILE)"
else
  echo "RPM build failed."
  exit 1
fi

echo
echo "Install with: sudo dnf install $OUTDIR/$(basename $RPMFILE)"
