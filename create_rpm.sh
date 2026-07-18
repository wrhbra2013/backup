#!/bin/bash
# ==============================================================================
# Criador Automático de RPM a partir de arquivos .tar.gz
# ==============================================================================

set -e

SCRIPT_VERSION="1.0"

print_usage() {
    cat <<EOF
Uso: $0 [OPÇÕES] arquivo.tar.gz

OPÇÕES:
    -n, --name         Nome do pacote (padrão: nome do arquivo sem extensão)
    -v, --version      Versão do pacote (padrão: extraída do nome ou 1.0)
    -r, --release      Release do pacote (padrão: 1)
    -d, --description  Descrição do pacote
    -l, --license      Licença (padrão: MIT)
    -p, --prefix       Prefixo de instalação (padrão: /usr/local)
    -m, --maintainer   Mantenedor do pacote
    --no-install       Apenas criar RPM, não instalar
    -h, --help         Mostrar esta ajuda

EXEMPLOS:
    $0 programa-1.0.0.tar.gz
    $0 -n meuprog -v 2.0 -d "Meu Programa" programa.tar.gz
EOF
    exit 0
}

check_deps() {
    MISSING=()
    for cmd in rpmbuild tar gzip; do
        if ! command -v $cmd &> /dev/null; then
            MISSING+=($cmd)
        fi
    done

    if [ ${#MISSING[@]} -gt 0 ]; then
        echo "Instalando dependências..."
        if command -v dnf &> /dev/null; then
            sudo dnf install -y "${MISSING[@]}" rpm-build
        elif command -v yum &> /dev/null; then
            sudo yum install -y "${MISSING[@]}" rpm-build
        fi
    fi
}

setup_rpmbuild() {
    RPMBUILD_DIR="$HOME/rpmbuild"
    for dir in BUILD BUILDROOT RPMS SOURCES SPECS SRPMS; do
        mkdir -p "$RPMBUILD_DIR/$dir"
    done
}

parse_name_version() {
    local archive="$1"
    local basename=$(basename "$archive" .tar.gz)
    
    if [[ "$basename" =~ ^(.+)-([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        PKG_NAME="${BASH_REMATCH[1]}"
        PKG_VERSION="${BASH_REMATCH[2]}"
    elif [[ "$basename" =~ ^(.+)-([0-9]+\.[0-9]+)$ ]]; then
        PKG_NAME="${BASH_REMATCH[1]}"
        PKG_VERSION="${BASH_REMATCH[2]}"
    else
        PKG_NAME="$basename"
        PKG_VERSION="1.0"
    fi
}

create_spec() {
    local archive="$1"
    local archive_name=$(basename "$archive")
    
    # Extrair temporariamente para descobrir o nome do diretório
    TEMP_DIR=$(mktemp -d)
    tar -xzf "$archive" -C "$TEMP_DIR"
    SOURCE_DIR=$(ls -1 "$TEMP_DIR" | head -1)
    SOURCE_PATH="$TEMP_DIR/$SOURCE_DIR"
    
    # Verificar se é binário pré-compilado ou código fonte
    if [ -f "$SOURCE_PATH/configure" ] || [ -f "$SOURCE_PATH/Makefile" ]; then
        HAS_BUILD=true
    else
        HAS_BUILD=false
    fi
    rm -rf "$TEMP_DIR"
    
    if [ "$HAS_BUILD" = true ]; then
        BUILD_SECTION="
%build
if [ -f configure ]; then
    ./configure --prefix=${PKG_PREFIX}
elif [ -f Makefile ]; then
    make
fi
make %{?_smp_mflags}

%install
make install DESTDIR=%{buildroot}"
    else
        BUILD_SECTION="
%install
mkdir -p %{buildroot}${PKG_PREFIX}
cp -r . %{buildroot}${PKG_PREFIX}/"
    fi
    
    cat > "$SPEC_FILE" <<EOF
Name:           ${PKG_NAME}
Version:        ${PKG_VERSION}
Release:        ${PKG_RELEASE}%{?dist}
Summary:        ${PKG_DESCRIPTION}
License:        ${PKG_LICENSE}
Packager:      ${PKG_MAINTAINER}
Source0:        %{name}-%{version}.tar.gz
Prefix:         ${PKG_PREFIX}

%description
${PKG_DESCRIPTION}

%prep
%setup -q -n ${SOURCE_DIR}
${BUILD_SECTION}

%files
%defattr(-,root,root,-)
${PKG_PREFIX}/*

%changelog
* $(date '+%a %b %d %Y') ${PKG_MAINTAINER} - ${PKG_VERSION}-${PKG_RELEASE}
- Pacote RPM criado automaticamente
EOF
}

build_rpm() {
    local archive="$1"
    local archive_name=$(basename "$archive")
    
    cp "$archive" "$SOURCES_DIR/"
    
    echo "=== Criando RPM..."
    
    # Obter tamanho do arquivo fonte para estimativa
    ARCHIVE_SIZE=$(stat -c%s "$archive" 2>/dev/null || stat -f%z "$archive" 2>/dev/null)
    ARCHIVE_SIZE_KB=$((ARCHIVE_SIZE / 1024))
    ESTIMATED_RPM_SIZE=$((ARCHIVE_SIZE_KB * 2))
    
    # Função para mostrar barra de progresso
    show_progress() {
        local percent=$1
        local width=40
        local filled=$((width * percent / 100))
        local empty=$((width - filled))
        
        printf "\r["
        printf "%${filled}s" | tr ' ' '█'
        printf "%${empty}s" | tr ' ' '░'
        printf "] %3d%%" "$percent"
    }
    
    # Função de cleanup
    cleanup() {
        kill $MONITOR_PID 2>/dev/null
        rm -f "$LOG_FILE"
    }
    trap cleanup EXIT
    
    LOG_FILE="/tmp/rpmbuild_$$.log"
    mkfifo "$LOG_FILE" 2>/dev/null
    
    # Monitor de progresso com estimativa baseada no tempo e tamanho
    (
        PHASES=("Preparando fontes" "Compilando código" "Instalando arquivos" "Gerando pacote RPM" "Verificando integridade")
        PHASE=0
        START_TIME=$(date +%s)
        LAST_PHASE=0
        
        while kill -0 $$ 2>/dev/null; do
            CURRENT_TIME=$(date +%s)
            ELAPSED=$((CURRENT_TIME - START_TIME))
            
            # Detectar fase pelo log
            if grep -q "Executing(%prep)" "$LOG_FILE" 2>/dev/null; then
                PHASE=0
            fi
            if grep -q "Executing(%build)" "$LOG_FILE" 2>/dev/null; then
                PHASE=1
            fi
            if grep -q "Executing(%install)" "$LOG_FILE" 2>/dev/null; then
                PHASE=2
            fi
            if grep -q "Creating.*rpm" "$LOG_FILE" 2>/dev/null || grep -q "Building target packages" "$LOG_FILE" 2>/dev/null; then
                PHASE=3
            fi
            if grep -q "Wrote:" "$LOG_FILE" 2>/dev/null; then
                PHASE=4
            fi
            
            # Calcular progresso
            BASE=$((PHASE * 20))
            
            # Adicionar progresso baseado no tempo gasto na fase
            if [ $PHASE -eq $LAST_PHASE ] && [ $ELAPSED -gt 0 ]; then
                TIME_BONUS=$(( (ELAPSED % 10) * 2 ))
            else
                TIME_BONUS=0
            fi
            
            PROGRESS=$((BASE + TIME_BONUS))
            [ $PROGRESS -gt 98 ] && PROGRESS=98
            [ $PROGRESS -lt 0 ] && PROGRESS=0
            
            LAST_PHASE=$PHASE
            
            # Mostrar tamanho estimado
            ESTIMATED_CURRENT=$((ESTIMATED_RPM_SIZE * PROGRESS / 100))
            
            printf "\r"
            show_progress $PROGRESS
            printf " %-25s | Est: ~%d KB" "${PHASES[$PHASE]}" "$ESTIMATED_CURRENT"
            
            sleep 0.2
        done
    ) &
    MONITOR_PID=$!
    
    # Executar rpmbuild
    rpmbuild -ba "$SPEC_FILE" > "$LOG_FILE" 2>&1
    RPM_EXIT=$?
    
    kill $MONITOR_PID 2>/dev/null
    wait $MONITOR_PID 2>/dev/null
    
    printf "\r"
    show_progress 100
    printf " Concluido!\n"
    
    rm -f "$LOG_FILE"
    
    if [ $RPM_EXIT -ne 0 ]; then
        echo "ERRO: Falha ao criar RPM (código: $RPM_EXIT)"
        echo "Verifique os logs em $HOME/rpmbuild/"
        cat "$HOME/rpmbuild/SPECS/${PKG_NAME}.log" 2>/dev/null || true
        exit 1
    fi
    
    local rpm_file=$(find "$RPMS_DIR" -name "*.rpm" -type f 2>/dev/null | head -1)
    
    if [ -n "$rpm_file" ]; then
        RPM_SIZE=$(du -h "$rpm_file" | cut -f1)
        RPM_SIZE_BYTES=$(stat -c%s "$rpm_file" 2>/dev/null || stat -f%z "$rpm_file" 2>/dev/null)
        RPM_SIZE_KB=$((RPM_SIZE_BYTES / 1024))
        
        echo ""
        echo "╔═══════════════════════════════════════════════════╗"
        echo "║          RPM CRIADO COM SUCESSO!                 ║"
        echo "╠═══════════════════════════════════════════════════╣"
        printf "║  Arquivo: %-40s║\n" "$rpm_file"
        printf "║  Tamanho: %-41s║\n" "$RPM_SIZE ($RPM_SIZE_KB KB)"
        echo "╚═══════════════════════════════════════════════════╝"
        echo ""
        
        if [ "$INSTALL_RPM" = true ]; then
            echo "Instalando RPM..."
            if sudo rpm -ivh "$rpm_file" 2>/dev/null; then
                echo "RPM instalado com sucesso!"
            else
                echo "Tentando atualização..."
                sudo rpm -Uvh "$rpm_file"
            fi
        fi
    else
        echo "ERRO: RPM não encontrado após build"
        exit 1
    fi
}

# ============================================
# MAIN
# ============================================

PKG_NAME=""
PKG_VERSION=""
PKG_RELEASE="1"
PKG_DESCRIPTION="Pacote criado automaticamente"
PKG_LICENSE="MIT"
PKG_PREFIX="/usr/local"
PKG_MAINTAINER="$USER"
INSTALL_RPM=true

if [ $# -eq 0 ]; then
    print_usage
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name) PKG_NAME="$2"; shift 2 ;;
        -v|--version) PKG_VERSION="$2"; shift 2 ;;
        -r|--release) PKG_RELEASE="$2"; shift 2 ;;
        -d|--description) PKG_DESCRIPTION="$2"; shift 2 ;;
        -l|--license) PKG_LICENSE="$2"; shift 2 ;;
        -p|--prefix) PKG_PREFIX="$2"; shift 2 ;;
        -m|--maintainer) PKG_MAINTAINER="$2"; shift 2 ;;
        --no-install) INSTALL_RPM=false; shift ;;
        -h|--help) print_usage ;;
        -*) echo "Opção desconhecida: $1"; exit 1 ;;
        *) ARCHIVE="$1"; shift ;;
    esac
done

if [ -z "$ARCHIVE" ]; then
    echo "ERRO: Arquivo .tar.gz não especificado"
    exit 1
fi

if [ ! -f "$ARCHIVE" ]; then
    echo "ERRO: Arquivo não encontrado: $ARCHIVE"
    exit 1
fi

if [[ ! "$ARCHIVE" =~ \.tar\.gz$ ]]; then
    echo "ERRO: Arquivo deve ter extensão .tar.gz"
    exit 1
fi

echo "=== Criador de RPM v${SCRIPT_VERSION} ==="
echo "Arquivo: $ARCHIVE"

check_deps
setup_rpmbuild
parse_name_version "$ARCHIVE"

[ -z "$PKG_NAME" ] && PKG_NAME="$parse_result_name"
[ -z "$PKG_VERSION" ] && PKG_VERSION="$parse_result_version"

RPMBUILD_DIR="$HOME/rpmbuild"
SOURCES_DIR="$RPMBUILD_DIR/SOURCES"
SPECS_DIR="$RPMBUILD_DIR/SPECS"
RPMS_DIR="$RPMBUILD_DIR/RPMS/x86_64"
SPEC_FILE="$SPECS_DIR/${PKG_NAME}.spec"

echo "Nome: $PKG_NAME"
echo "Versão: $PKG_VERSION"
echo "Release: $PKG_RELEASE"
echo ""

create_spec "$ARCHIVE"
build_rpm "$ARCHIVE"
