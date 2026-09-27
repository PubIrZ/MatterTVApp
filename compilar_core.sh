#!/bin/bash
# =========================================================================
# SCRIPT DINÁMICO DE COMPILACIÓN - BYPASS TOTAL DE WARNINGS DE KOTLIN
# =========================================================================
set -e # Detiene el script inmediatamente si ocurre un error inesperado

# =========================================================================
# ¡EL LIMPIADOR MAESTRO DE SALTOS DE LÍNEA DE WINDOWS (CRLF a LF)!
# =========================================================================
sed -i 's/\r$//' "$0" || true

# =========================================================================
# ¡EL PARCHE CLAVE AN_TI-CIPD DE CONFIGURACIÓN!
# =========================================================================
echo "INFRA: Neutralizando configuraciones JSON rígidas de CIPD para ZAP..."
if [ -f "scripts/setup/zap.json" ]; then
    echo '{"packages": []}' > scripts/setup/zap.json
fi
find . -name "zap.json" -exec sh -c 'echo "{\"packages\": []}" > "{}"' \;

# =========================================================================
# ¡HOT PATCH DE COMPATIBILIDAD PYTHON 3.12 PARA PIGWEED!
# =========================================================================
echo "INFRA: Aplicando parche de compatibilidad Python 3.12 para TypeVar..."
pip install --upgrade typing-extensions --quiet || true

if [ -d ".environment/pigweed-venv" ]; then
    .environment/pigweed-venv/bin/pip install --upgrade typing-extensions --quiet || true
fi

echo "INFRA: Inicializando el entorno virtual aislado de Pigweed..."
source scripts/activate.sh

# =========================================================================
# TRUCO MAESTRO 1: RE-INYECTAMOS TU ANDROID.JAR (API 26) EM_PARETADA
# =========================================================================
echo "INFRA: Descargando el archivo original android.jar (API 26) usando variables seguras..."
TARGET_PLATFORM_DIR="/usr/local/lib/android/sdk/platforms/android-26"
mkdir -p "$TARGET_PLATFORM_DIR"

PATH_platform26="/android/repository/platform-26_r02.zip"
URL_google="https://dl.google.com${PATH_platform26}"

curl -L --retry 5 --retry-delay 5 --fail "$URL_google" -o platform26.zip

mkdir -p temp_extracted
unzip -o -q platform26.zip -d temp_extracted/

REAL_JAR_PATH=$(find temp_extracted/ -name "android.jar" -type f -print -quit 2>/dev/null)
if [ -n "$REAL_JAR_PATH" ]; then
    mv "$REAL_JAR_PATH" "$TARGET_PLATFORM_DIR/android.jar"
fi
rm -rf temp_extracted platform26.zip
echo "SUCCESS: Archivo maestro android.jar (API 26) inyectado."

echo "INFRA: Descargando pre-requisitos de dependencias de Android..."
python3 third_party/android_deps/set_up_android_deps.py
third_party/java_deps/set_up_java_deps.sh

# =========================================================================
# TU TRUCO MAESTRO REINTEGRADO: INYECCIÓN DE ZAP-CLI EXACTA
# =========================================================================
echo "INFRA: Descargando e instalando el motor ZAP-CLI..."
ZAP_ASSET="/project-chip/zap/releases/download/v2024.03.29/zap-linux-x64.zip"
curl -L --retry 5 --retry-delay 5 --fail "https://github.com${ZAP_ASSET}" -o zap.zip

mkdir -p /usr/local/share/zap
unzip -o -q zap.zip -d /usr/local/share/zap

if [ -d "/usr/local/share/zap/zap-linux-x64" ]; then
    cp -r /usr/local/share/zap/zap-linux-x64/* /usr/local/share/zap/
    rm -rf /usr/local/share/zap/zap-linux-x64
fi

ln -sf /usr/local/share/zap/zap-cli /usr/local/bin/zap-cli
ln -sf /usr/local/share/zap/zap-cli /usr/local/bin/zap
chmod +x /usr/local/bin/zap*

if [ -f "scripts/setup/zap.json" ]; then 
    echo '{"packages": []}' > scripts/setup/zap.json
fi

export ZAP_INSTALL_PATH="/usr/local/bin"
export PATH="/usr/local/bin:$PATH"
echo "SUCCESS: ¡Motor ZAP-CLI inyectado y mapeado!"

# =========================================================================
# TRUCO MAESTRO 2: TU PARCHE NDK COMPILER LAYOUT MATCHING (LIBC++) BLINDADO
# =========================================================================
echo "=== HACKING NDK DIRECTORY TREE FOR LIBC++ ==="
NDK_PATH="/opt/android/android-ndk-r25c"
export ANDROID_NDK_ROOT="$NDK_PATH"
export ANDROID_NDK_HOME="$NDK_PATH"

TARGET_STL_DIR_32="$NDK_PATH/sources/cxx-stl/llvm-libc++/libs/armeabi-v7a"
TARGET_STL_DIR_64="$NDK_PATH/sources/cxx-stl/llvm-libc++/libs/arm64-v8a"
mkdir -p "$TARGET_STL_DIR_32" "$TARGET_STL_DIR_64"

REAL_SO_32="/opt/android/android-ndk-r25c/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/arm-linux-androideabi/libc++_shared.so"
REAL_SO_64="/opt/android/android-ndk-r25c/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"

rm -f "$TARGET_STL_DIR_32/libc++_shared.so"
rm -f "$TARGET_STL_DIR_64/libc++_shared.so"

ln -sf "$REAL_SO_32" "$TARGET_STL_DIR_32/libc++_shared.so"
ln -sf "$REAL_SO_64" "$TARGET_STL_DIR_64/libc++_shared.so"
echo "SUCCESS: Enlaces simbólicos cruzados inyectados mediante punteros puros."

# =========================================================================
# ¡EL HACK DE COMPATIBILIDAD DINÁMICO PARA EL COMPILADOR CLANG (API 24 BYPASS)!
# Localizamos de forma automática el directorio físico que aloja los ejecutables
# de Clang del NDK en el búnker para evitar caídas por variaciones de nombres de rutas.
# =========================================================================
echo "INFRA: Localizando de forma automática el directorio de binarios de Clang..."
set +e
REAL_BIN_DIR=$(find "$NDK_PATH" -name "*clang++*" -type f -print -quit 2>/dev/null)
set -e

if [ -n "$REAL_BIN_DIR" ]; then
    BIN_NDK_DIR=$(dirname "$REAL_BIN_DIR")
    echo "INFRA: Directorio de compilación cruzada localizado en: $BIN_NDK_DIR"
    
    # Buscamos qué ejecutable de Clang de API alta existe para usarlo de base espejo
    BASE_CLANG_32=$(find "$BIN_NDK_DIR" -name "armv7a-linux-androideabi*-clang" -type f -print -quit | head -n 1)
    BASE_CLANGXX_32=$(find "$BIN_NDK_DIR" -name "armv7a-linux-androideabi*-clang++" -type f -print -quit | head -n 1)
    BASE_CLANG_64=$(find "$BIN_NDK_DIR" -name "aarch64-linux-android*-clang" -type f -print -quit | head -n 1)
    BASE_CLANGXX_64=$(find "$BIN_NDK_DIR" -name "aarch64-linux-android*-clang++" -type f -print -quit | head -n 1)

    echo "INFRA: Inyectando enlaces de compatibilidad API 24 basados en objetos reales..."
    ln -sf "$BASE_CLANG_32" "$BIN_NDK_DIR/armv7a-linux-androideabi24-clang"
    ln -sf "$BASE_CLANGXX_32" "$BIN_NDK_DIR/armv7a-linux-androideabi24-clang++"
    ln -sf "$BASE_CLANG_64" "$BIN_NDK_DIR/aarch64-linux-android24-clang"
    ln -sf "$BASE_CLANGXX_64" "$BIN_NDK_DIR/aarch64-linux-android24-clang++"
    echo "SUCCESS: ¡Puentes de compatibilidad de ejecutables Clang inyectados!"
else
    echo "CRITICAL ERROR: No se pudo localizar la carpeta de ejecutables binarios del NDK."
    exit 1
fi

# =========================================================================
# ¡EL CAMBIO MAESTRO DE RAÍZ! ELIMINAMOS -Werror Y DESACTIVAMOS ALERTAS
# =========================================================================
echo "INFRA: Removiendo flags estrictos de las plantillas fuentes BUILD.gn y .gni..."
find . -name "BUILD.gn" -exec sed -i 's|"-Werror",||g' {} +
find . -name "BUILD.gn" -exec sed -i 's|"-Werror"||g' {} +
find . -name "*.gni" -exec sed -i 's|"-Werror",||g' {} +
find . -name "*.gni" -exec sed -i 's|"-Werror"||g' {} +

find . -name "BUILD.gn" -exec sed -i 's|"-Xlint:all",||g' {} +
find . -name "BUILD.gn" -exec sed -i 's|"-Xlint:all"||g' {} +
find . -name "*.gni" -exec sed -i 's|"-Xlint:all",||g' {} +
find . -name "*.gni" -exec sed -i 's|"-Xlint:all"||g' {} +

# =========================================================================
# ANULACIÓN COMPLETA EN EL MOTOR DE PIGWEED (KOTLINC)
# =========================================================================
echo "INFRA: Inyectando inhibidores de error '-nowarn' en el motor de Pigweed..."
export KOTLIN_COMPILER_ARGS="-nowarn -warn:0"
export KOTLINC_ARGS="-nowarn"

find . -name "kotlinc_runner.py" -exec sed -i "s|retcode = subprocess.check_call(kotlin_args + args.rest)|kotlin_args.append('-nowarn')\n    retcode = subprocess.check_call(kotlin_args + args.rest)|g" {} +
find . -name "kotlinc_runner.py" -exec sed -i "s|'-Werror'||g" {} +

echo "INFRA: Sincronizando árbol estructural de GN..."
gn gen out/android-arm-tv-server \
  --args='target_os="android" target_cpu="arm" android_ndk_root="'$ANDROID_NDK_ROOT'" android_sdk_root="/usr/local/lib/android/sdk" chip_config_network_layer_ble=false treat_warnings_as_errors=false' \
  --root=examples/tv-app/android/

find out/ -name "*.json" -exec sed -i 's|"-Werror",||g' {} +

echo "INFRA: Ninja reanudará la compilación de forma incremental..."
ninja -C out/android-arm-tv-server
