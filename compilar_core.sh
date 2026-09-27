#!/bin/bash 
# =========================================================================
# SCRIPT DE COMPILACIÓN NATIVO - ENTORNO CONGELADO MATTER 1.3 (API 24)
# =========================================================================
set -e # Detiene el script inmediatamente ante cualquier fallo inesperado

# Limpiador maestro de saltos de línea de Windows (CRLF a LF) por seguridad
sed -i 's/\r$//' "$0" || true

echo "INFRA: Inicializando el entorno virtual aislado de Pigweed en el búnker..."
# Activamos el entorno de desarrollo nativo que ya viene preparado en la imagen base
source scripts/activate.sh

echo "=== CONFIGURANDO VARIABLES DE ENTORNO NATIVAS DEL DOCKER ==="
# En la imagen chip-build-android:126, el SDK y NDK ya están preinstalados en estas rutas
export ANDROID_HOME="/opt/android/sdk"
export ANDROID_NDK_HOME="/opt/android/android-ndk-r23c"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"

# Aseguramos que los compiladores cruzados del NDK estén inmediatamente en el PATH
export PATH="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"

# =========================================================================
# PURGA QUIRÚRGICA DE FLAGS DE COMPILACIÓN (KOTLINC / JAVA LINTERS)
# =========================================================================
echo "INFRA: Desactivando alertas estrictas y flags de linter incompatibles con Kotlin..."
export KOTLIN_COMPILER_ARGS="-nowarn -warn:0"
export KOTLINC_ARGS="-nowarn"

# Inyectamos el inhibidor de alertas en el ejecutable intermedio de Pigweed
find . -name "kotlinc_runner.py" -exec sed -i "s|retcode = subprocess.check_call(kotlin_args + args.rest)|kotlin_args.append('-nowarn')\n    retcode = subprocess.check_call(kotlin_args + args.rest)|g" {} +

# Eliminamos banderas estrictas -Werror de las plantillas para evitar caídas por warnings tipográficos
find . -type f \( -name "BUILD.gn" -o -name "*.gni" \) -exec sed -i 's|"-Werror",||g' {} + 2>/dev/null || true
find . -type f \( -name "BUILD.gn" -o -name "*.gni" \) -exec sed -i 's|"-Werror"||g' {} + 2>/dev/null || true

# =========================================================================
# PUNTO DE LIMPIEZA SEGURO (MANTENER COMENTADO SALVO NECESIDAD DE RECONSTRUCCIÓN)
# =========================================================================
# Si la caché se corrompe o quieres compilar en limpio desde cero de forma segura
# SIN destruir los archivos fuente de ZAP (Accessors.cpp), descomenta la siguiente línea:
#
# gn clean out/android-arm-tv-server
#
# =========================================================================

# =========================================================================
# GENERACIÓN DE ENTORNO GN (Alineado con los fuentes nativos de la rama v1.3)
# =========================================================================
echo "INFRA: Sincronizando árbol estructural de GN (Mapeo incremental)..."
# Usamos las variables estándar. GN autodetectará la API 24 definida en build/toolchain/android/BUILD.gn
gn gen out/android-arm-tv-server \
  --args="target_os=\"android\" target_cpu=\"arm\" android_ndk_root=\"$ANDROID_NDK_ROOT\" android_sdk_root=\"$ANDROID_HOME\" chip_config_network_layer_ble=false treat_warnings_as_errors=false" \
  --root=examples/tv-app/android/

# =========================================================================
# PURGA POST-GN EN ARTEFACTOS GENERADOS
# =========================================================================
echo "INFRA: Limpiando referencias de warnings remanentes en los perfiles de Ninja..."
find out/ -name "*.json" -exec sed -i 's|"-Werror",||g' {} + 2>/dev/null || true
find out/ -name "*.json" -exec sed -i 's|"-Xlint:deprecation",||g' {} + 2>/dev/null || true
find out/ -name "*.ninja" -exec sed -i 's|-Xlint:deprecation||g' {} + 2>/dev/null || true

# =========================================================================
# COMPILACIÓN MAESTRA INCREMENTAL CON NINJA
# =========================================================================
echo "INFRA: Ejecutando Ninja. El búnker procesará la compilación de forma segura..."
ninja -C out/android-arm-tv-server
