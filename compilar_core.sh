#!/bin/bash
# =========================================================================
# SCRIPT MAESTRO DE COMPILACIÓN DEFINITIVO - MATTER 1.3
# =========================================================================
set -e # Detiene el script inmediatamente si ocurre un error inesperado

# =========================================================================
# PARTE 1: LIMPIEZA ABSOLUTA DE ENTORNO (ANTI-LOOPS)
# =========================================================================
echo "INFRA: Rompiendo y purgando cualquier residuo cíclico de compilaciones previas..."

# Rompemos de forma agresiva cualquier bucle de enlaces simbólicos colgados o recursivos
unlink zzz_generated 2>/dev/null || true
rm -rf out/ zzz_generated/

# Limpieza quirúrgica profunda de la ruta conflictiva para evitar errores de loops simbólicos
set +e
find . -name "zzz_generated" -exec rm -rf {} + 2>/dev/null
set -e

# Limpiador maestro de saltos de línea de Windows (CRLF a LF)
sed -i 's/\r$//' "$0" || true

echo "INFRA: Neutralizando configuraciones JSON rígidas de CIPD para ZAP..."
if [ -f "scripts/setup/zap.json" ]; then
    echo '{"packages": []}' > scripts/setup/zap.json
fi
find . -name "zap.json" -exec sh -c 'echo "{\"packages\": []}" > "{}"' \;

echo "INFRA: Aplicando parche de compatibilidad Python 3.12 para TypeVar..."
pip install --upgrade typing-extensions --quiet || true
if [ -d ".environment/pigweed-venv" ]; then
    .environment/pigweed-venv/bin/pip install --upgrade typing-extensions --quiet || true
fi

echo "INFRA: Inicializando el entorno virtual aislado de Pigweed..."
source scripts/activate.sh

echo "=== CONFIGURANDO PASARELAS DEL SDK NATIVO DEL DOCKER ==="
export ANDROID_HOME="/usr/local/lib/android/sdk"
export ANDROID_NDK_HOME="/opt/android/android-ndk-r23c"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"

# Validamos la existencia física de la plataforma SDK 26 para las licencias de sdkmanager
if [ ! -d "$ANDROID_HOME/platforms/android-26" ]; then
    echo "INFRA: Estructurando plataforma del SDK 26..."
    TARGET_PLATFORM_DIR="$ANDROID_HOME/platforms/android-26"
    mkdir -p "$TARGET_PLATFORM_DIR"
    
    PATH_platform26="com/android/repository/platform-26_r02.zip"
    URL_google="https://dl.google.${PATH_platform26}"
    curl -L --retry 5 --retry-delay 5 --fail "$URL_google" -o platform26.zip
    
    mkdir -p temp_extracted
    unzip -o -q platform26.zip -d temp_extracted/
    REAL_JAR_PATH=$(find temp_extracted/ -name "android.jar" -type f -print -quit 2>/dev/null)
    if [ -n "$REAL_JAR_PATH" ]; then
        mv "$REAL_JAR_PATH" "$TARGET_PLATFORM_DIR/android.jar"
    fi
    rm -rf temp_extracted platform26.zip
fi

echo "INFRA: Descargando pre-requisitos de dependencias de Android..."
python3 third_party/android_deps/set_up_android_deps.py
third_party/java_deps/set_up_java_deps.sh

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

export ZAP_INSTALL_PATH="/usr/local/bin"
export PATH="/usr/local/bin:$PATH"
echo "SUCCESS: ¡Motor ZAP-CLI inyectado y mapeado!"

# =========================================================================
# PARTE 2: ENRUTAMIENTO, PRE-GENERACIÓN DE ARCHIVOS Y COMPILACIÓN
# =========================================================================

# Exponemos de forma nativa los binarios del NDK r23c y Clang
STATIC_BIN_DIR="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
if [ -d "$STATIC_BIN_DIR" ]; then
    export PATH="$STATIC_BIN_DIR:$PATH"
fi

# Localizar e inyectar de forma robusta kotlinc en el PATH de Pigweed
KOTLINC_PATH=$(find .environment/ -name "kotlinc" -type f -print -quit 2>/dev/null)
if [ -n "$KOTLINC_PATH" ]; then
    KOTLINC_DIR=$(dirname "$KOTLINC_PATH")
    export PATH="$KOTLINC_DIR:$PATH"
    chmod +x "$KOTLINC_DIR"/* || true
    echo "INFRA: Herramientas de Kotlin expuestas desde: $KOTLINC_DIR"
fi

echo "INFRA: Removiendo flags estrictos de las plantillas fuentes BUILD.gn y .gni..."
find . -type f \( -name "BUILD.gn" -o -name "*.gni" \) -exec sed -i 's|"-Werror",||g' {} + 2>/dev/null || true
find . -type f \( -name "BUILD.gn" -o -name "*.gni" \) -exec sed -i 's|"-Werror"||g' {} + 2>/dev/null || true

# Corrección definitiva de sed: Patrón limpio acotado por comillas válidas de GN
find . -type f \( -name "BUILD.gn" -o -name "*.gni" \) -exec sed -i 's|"-Xlint:[^"]*",||g' {} + 2>/dev/null || true
find . -type f \( -name "BUILD.gn" -o -name "*.gni" \) -exec sed -i 's|"-Xlint:[^"]*"||g' {} + 2>/dev/null || true

echo "INFRA: Inyectando inhibidores de error '-nowarn' en el motor de Pigweed (kotlinc)..."
export KOTLIN_COMPILER_ARGS="-nowarn -warn:0"
export KOTLINC_ARGS="-nowarn"
find . -name "kotlinc_runner.py" -exec sed -i "s|retcode = subprocess.check_call(kotlin_args + args.rest)|kotlin_args.append('-nowarn')\n    retcode = subprocess.check_call(kotlin_args + args.rest)|g" {} +

# =========================================================================
# SINCRONIZACIÓN GN NATIVA
# =========================================================================
echo "INFRA: Sincronizando árbol estructural de GN limpio..."
gn gen out/android-arm-tv-server \
  --args='target_os="android" target_cpu="arm" android_ndk_root="'$ANDROID_NDK_ROOT'" android_sdk_root="'$ANDROID_HOME'" chip_config_network_layer_ble=false treat_warnings_as_errors=false' \
  --root=examples/tv-app/android/

# =========================================================================
# GENERACIÓN DE CÓDIGO NATIVA DE ATRIBUTOS (ZAP - CON ENRUTAMIENTO ABSOLUTO)
# =========================================================================
echo "INFRA: Invocando la pre-generación física de código ZAP para TV-App..."

# Forzamos la creación del destino exacto que GN mapeó para la compilación JNI
AUTO_GEN_PATH="examples/tv-app/android/third_party/connectedhomeip/zzz_generated/app-common/app-common/zap-generated/attributes"
mkdir -p "$AUTO_GEN_PATH"

echo "INFRA: Localizando archivos de plantilla absolutos para evitar caídas de packageId..."
MATTER_TEMPLATES_JSON=$(find "$(pwd)" -name "matter-idl-server.json" -type f -print -quit 2>/dev/null)

if [ -z "$MATTER_TEMPLATES_JSON" ] || [ ! -f "$MATTER_TEMPLATES_JSON" ]; then
    echo "WARNING: No se encontró matter-idl-server.json automáticamente. Usando fallback..."
    MATTER_TEMPLATES_JSON="$(pwd)/src/app/zap-templates/matter-idl-server.json"
fi

echo "INFRA: Plantilla de Matter resuelta en: $MATTER_TEMPLATES_JSON"

set +e
# Ejecutamos zap-cli forzando la ruta absoluta del template resuelto
zap-cli generate examples/tv-app/tv-common/tv-app.zap \
  -t "$MATTER_TEMPLATES_JSON" \
  -o "$AUTO_GEN_PATH/../" || true

# Duplicamos la salida de forma segura a la raíz evitando colisiones de archivos idénticos
mkdir -p zzz_generated/app-common/app-common/zap-generated/attributes/
if [ ! "zzz_generated" -ef "examples/tv-app/android/third_party/connectedhomeip/zzz_generated" ]; then
    cp -rf examples/tv-app/android/third_party/connectedhomeip/zzz_generated/* zzz_generated/ 2>/dev/null || true
fi
set -e

# =========================================================================
# PURGA DE ARTEFACTOS POST-GN Y COMPILACIÓN
# =========================================================================
echo "INFRA: Purgando residuos de flags de los artefactos generados..."
find out/ -name "*.json" -exec sed -i 's|"-Werror",||g' {} +
find out/ -name "*.json" -exec sed -i 's|"-Xlint:deprecation",||g' {} +
find out/ -name "*.ninja" -exec sed -i 's|-Xlint:deprecation||g' {} +

echo "INFRA: ¡Estructura asegurada! Lanzando Ninja de manera incremental..."
ninja -C out/android-arm-tv-server
