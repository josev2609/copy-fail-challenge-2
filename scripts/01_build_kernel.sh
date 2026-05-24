#!/usr/bin/env bash
# scripts/01_build_kernel.sh
set -euo pipefail

KERNEL_TAG="${KERNEL_TAG:-v6.12}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL_SRC="$WORKSPACE_ROOT/kernel/linux"
BUILD_DIR="$WORKSPACE_ROOT/kernel/build"
JOBS=$(nproc)

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RED='\033[1;31m'
NC='\033[0m'

echo -e "${CYAN}[1/5] Clonando kernel ${KERNEL_TAG}...${NC}"

if [ ! -d "$KERNEL_SRC" ]; then
  git clone --depth 1 --branch "$KERNEL_TAG" https://github.com/torvalds/linux.git "$KERNEL_SRC"
else
  echo -e "${YELLOW}Kernel source ya existe, omitiendo clone.${NC}"
fi

cd "$KERNEL_SRC"

echo -e "${CYAN}[2/5] Guardando hash del commit...${NC}"
VULN_HASH=$(git rev-parse HEAD)
mkdir -p "$WORKSPACE_ROOT/kernel"
echo "$VULN_HASH" > "$WORKSPACE_ROOT/kernel/vuln_commit.txt"

echo -e "${CYAN}[3/5] Configurando el kernel tinyconfig...${NC}"

make tinyconfig

# Arquitectura 64 bits
scripts/config --enable 64BIT

# Consola serial para QEMU
scripts/config --enable SERIAL_8250
scripts/config --enable SERIAL_8250_CONSOLE
scripts/config --enable TTY
scripts/config --enable VT
scripts/config --enable UNIX98_PTYS

# Initramfs
scripts/config --enable BLK_DEV_INITRD
scripts/config --enable INITRAMFS_SOURCE

# IMPORTANTE:
# Forzar GZIP y desactivar XZ para evitar errores/memoria en Codespaces
scripts/config --disable KERNEL_XZ
scripts/config --enable KERNEL_GZIP
scripts/config --enable RD_GZIP
scripts/config --disable RD_XZ

# Formatos ejecutables
scripts/config --enable BINFMT_ELF
scripts/config --enable BINFMT_SCRIPT

# Filesystems básicos
scripts/config --enable TMPFS
scripts/config --enable PROC_FS
scripts/config --enable SYSFS
scripts/config --enable DEVTMPFS
scripts/config --enable DEVTMPFS_MOUNT

# Red básica
scripts/config --enable NET
scripts/config --enable UNIX
scripts/config --enable INET
scripts/config --enable PACKET

# Módulos Crypto vulnerables / AF_ALG
# Módulos Crypto vulnerables / AF_ALG
scripts/config --enable CRYPTO
scripts/config --enable CRYPTO_ALGAPI
scripts/config --enable CRYPTO_MANAGER
scripts/config --enable CRYPTO_USER
scripts/config --enable CRYPTO_USER_API
scripts/config --enable CRYPTO_USER_API_AEAD
scripts/config --enable CRYPTO_USER_API_SKCIPHER

# AEAD / authenc / authencesn
scripts/config --enable CRYPTO_AEAD
scripts/config --enable CRYPTO_AUTHENC
scripts/config --enable CRYPTO_AUTHENCESN

# Algoritmos usados por authencesn(hmac(sha256),cbc(aes))
scripts/config --enable CRYPTO_AES
scripts/config --enable CRYPTO_CBC
scripts/config --enable CRYPTO_HMAC
scripts/config --enable CRYPTO_SHA256

# IV generators necesarios en varios modos AEAD
scripts/config --enable CRYPTO_ECHAINIV
scripts/config --enable CRYPTO_SEQIV
scripts/config --enable CRYPTO_ALGAPI
scripts/config --enable CRYPTO_MANAGER

# Usuarios, permisos y setuid
scripts/config --enable MULTIUSER

# Logs y debug mínimo
scripts/config --enable PRINTK
scripts/config --enable EARLY_PRINTK

make olddefconfig

echo -e "${CYAN}Verificando compresión del kernel:${NC}"
grep -E "CONFIG_KERNEL_XZ|CONFIG_KERNEL_GZIP|CONFIG_RD_XZ|CONFIG_RD_GZIP" .config || true

echo -e "${CYAN}[4/5] Compilando bzImage...${NC}"

make -j"$JOBS" bzImage

mkdir -p "$BUILD_DIR"
cp arch/x86/boot/bzImage "$BUILD_DIR/bzImage_vuln"

echo -e "${GREEN}[5/5] ✓ Kernel listo en kernel/build/bzImage_vuln${NC}"
ls -lh "$BUILD_DIR/bzImage_vuln"