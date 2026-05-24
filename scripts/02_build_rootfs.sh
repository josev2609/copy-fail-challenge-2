#!/usr/bin/env bash
# scripts/02_build_rootfs.sh
# Construye el initramfs de la prueba + Inyección del Exploit en C + Interfaz Gráfica ASCII
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUSYBOX_SRC="$WORKSPACE_ROOT/kernel/busybox"
INITRAMFS_DIR="$WORKSPACE_ROOT/kernel/initramfs"
BUILD_DIR="$WORKSPACE_ROOT/kernel/build"
JOBS=$(nproc)

GREEN='\033[1;32m'; CYAN='\033[1;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${CYAN}[1/6] Clonando BusyBox...${NC}"
if [ ! -d "$BUSYBOX_SRC" ]; then
  git clone --depth 1 https://git.busybox.net/busybox "$BUSYBOX_SRC"
fi

cd "$BUSYBOX_SRC"
echo -e "${CYAN}[2/6] Configurando BusyBox (estático)...${NC}"
make defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
grep -q "CONFIG_STATIC=y" .config || echo "CONFIG_STATIC=y" >> .config
sed -i 's/CONFIG_TC=y/CONFIG_TC=n/' .config   

echo -e "${CYAN}[3/6] Compilando BusyBox...${NC}"
make -j"$JOBS" 2>&1 | tail -3

echo -e "${CYAN}[4/6] Instalando BusyBox...${NC}"
mkdir -p "$INITRAMFS_DIR"
make CONFIG_PREFIX="$INITRAMFS_DIR" install

# Estructura del sistema jerárquico UNIX
mkdir -p "$INITRAMFS_DIR"/{proc,sys,dev,tmp,etc,root,home/student,usr/bin,lib,lib64,run}

echo -e "${CYAN}[5/6] Incluyendo Python 3 y arreglando enlazadores...${NC}"
PYTHON_BIN=$(which python3)
cp "$PYTHON_BIN" "$INITRAMFS_DIR/usr/bin/python3"

# Copia del cargador dinámico real para asegurar que no dé Error -2
cp -LH /lib64/ld-linux-x86-64.so.2 "$INITRAMFS_DIR/lib64/" 2>/dev/null || true

# Copiar librerías dinámicas rompiendo enlaces simbólicos rotos (-LH)
for lib in $(ldd "$PYTHON_BIN" 2>/dev/null | grep -oE '/[^ ]+\.so[^ ]*'); do
  mkdir -p "$INITRAMFS_DIR$(dirname $lib)"
  cp -LH "$lib" "$INITRAMFS_DIR$lib" 2>/dev/null || true
done

PYTHON_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
mkdir -p "$INITRAMFS_DIR/usr/lib/python${PYTHON_VER}"
cp -r /usr/lib/python3/* "$INITRAMFS_DIR/usr/lib/" 2>/dev/null || \
  cp -r /usr/lib/python${PYTHON_VER} "$INITRAMFS_DIR/usr/lib/" 2>/dev/null || true
ln -sf python3 "$INITRAMFS_DIR/usr/bin/python" 2>/dev/null || true

# Configuración de usuarios locales
cat > "$INITRAMFS_DIR/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/sh
student:x:1001:1001:student:/home/student:/bin/sh
EOF

cat > "$INITRAMFS_DIR/etc/shadow" << 'EOF'
root::19000:0:99999:7:::
student:$6$salt$hashedpassword:19000:0:99999:7:::
EOF

cat > "$INITRAMFS_DIR/etc/group" << 'EOF'
root:x:0:
student:x:1001:student
EOF

# /etc/profile con la bienvenida al iniciar la shell interactiva
cat > "$INITRAMFS_DIR/etc/profile" << 'EOF'
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PS1='[\u@copy-fail \w]\$ '
echo ""
echo "  Bienvenido al kernel vulnerable (CVE-2026-31431)"
echo "  Usuario: $(id)"
echo "  Kernel:  $(uname -r)"
echo ""
EOF

# ── Script init de arranque de la máquina virtual con interfaz ASCII ─────────────────
cat > "$INITRAMFS_DIR/init" << 'INITEOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null || mdev -s
mount -t tmpfs none /tmp

modprobe algif_aead 2>/dev/null || true
modprobe authencesn 2>/dev/null || true

# Hostname identificador (para validación anti-copia)
STUDENT_ID="${STUDENT_ID:-unknown}"
hostname "copy-fail-${STUDENT_ID}"

# =================================================================
# PARTE GRÁFICA ORIGINAL DEL PROFESOR (BANNER ASCII)
# =================================================================
echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   KERNEL VULNERABLE — CVE-2026-31431     ║"
echo "  ║   $(uname -r | cut -c1-42)               ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""

# Iniciar SSH daemon si existe
if [ -x /usr/sbin/sshd ]; then
  /usr/sbin/sshd -D &
fi

exec su - student
INITEOF
chmod +x "$INITRAMFS_DIR/init"

# =================================================================
# INTEGRACIÓN DEL RETO: INYECCIÓN DEL EXPLOIT EN C CON PERMISOS NORMALES
# =================================================================
if [ -f "$WORKSPACE_ROOT/exploit" ]; then
    echo -e "${GREEN} -> Inyectando binario estático real en el rootfs...${NC}"
    cp "$WORKSPACE_ROOT/exploit" "$INITRAMFS_DIR/home/student/exploit"
    
    # Contexto: Pertenece a student (1001) y sin bit SUID (0755)
    chown 1001:1001 "$INITRAMFS_DIR/home/student/exploit"
    chmod 0755 "$INITRAMFS_DIR/home/student/exploit"
else
    echo -e "${YELLOW} ⚠ ALERTA: No se encontró el binario '$WORKSPACE_ROOT/exploit'. Asegúrate de compilarlo en la raíz primero.${NC}"
fi
# =================================================================

echo -e "${CYAN}[6/6] Empaquetando...${NC}"
cd "$INITRAMFS_DIR"
find . | cpio -o -H newc 2>/dev/null | gzip > "$BUILD_DIR/initramfs.cpio.gz"
echo -e "${GREEN}✓ rootfs listo ${NC}"