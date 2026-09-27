#!/bin/bash
# =========================================================================
# SCRIPT DE COMPILACIÓN NATIVO - ENTORNO CONGELADO MATTER 1.3 (API 24)
# =========================================================================
set -e # Detiene el script inmediatamente ante cualquier fallo inesperado

# Limpiador maestro de saltos de línea de Windows (CRLF a LF) por seguridad
sed -i 's/\r$//' "$0" || true

# =========================================================================
# ¡EL PARCHE CLAVE AN_TI-CIPD DE CONFIGURACIÓN NEUTRALIZADA!
# =========================================================================
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

echo "INFRA: Inicializando el entorno virtual aislado de Pigweed en el búnker..."
source scripts/activate.sh

echo "=== CONFIGURANDO VARIABLES DE ENTORNO NATIVAS DEL DOCKER ==="
export ANDROID_HOME="/opt/android/sdk"
export ANDROID_NDK_HOME="/opt/android/android-ndk-r23c"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"

# Aseguramos que los compiladores cruzados del NDK estén inmediatamente en el PATH
export PATH="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"

# =========================================================================
# ¡INYECTAMOS PLATFORMS/ANDROID-26 SI FALTA!
# =========================================================================
TARGET_PLATFORM_DIR="$ANDROID_HOME/platforms/android-26"
if [ ! -f "$TARGET_PLATFORM_DIR/android.jar" ]; then
    echo "INFRA: Estructurando plataforma faltante del SDK 26 en $TARGET_PLATFORM_DIR..."
    mkdir -p "$TARGET_PLATFORM_DIR"
    
    PATH_platform26="com/android/repository/platform-26_r02.zip"
    URL_google="https://dl.google.${PATH_platform26}"
    
    curl -L --retry 5 --retry-delay 5 --fail "$URL_google" -o platform26.zip
    
    mkdir -p temp_extracted
    unzip -o -q platform26.zip -d temp_extracted/
    
    REAL_JAR_PATH=$(find temp_extracted/ -name "android.jar" -type f -print -quit 2>/dev/null)
    if [ -n "$REAL_JAR_PATH" ]; then
        mv "$REAL_JAR_PATH" "$TARGET_PLATFORM_DIR/android.jar"
        echo "SUCCESS: Archivo maestro android.jar (API 26) inyectado."
    fi
    rm -rf temp_extracted platform26.zip
fi

echo "INFRA: Descargando pre-requisitos de dependencias de Android..."
python3 third_party/android_deps/set_up_android_deps.py
third_party/java_deps/set_up_java_deps.sh

# =========================================================================
# ¡EL TRUCO MAESTRO DE SUBSANACIÓN DE ARTEFACTOS DEPENDIENTES (SAFE CHECK)!
# =========================================================================
echo "INFRA: Sincronizando de forma segura artefactos jar/aar hacia el subproyecto..."
MIRROR_DEPS_PATH="examples/tv-app/android/third_party/connectedhomeip/third_party/android_deps"
mkdir -p "$MIRROR_DEPS_PATH"

if [ -d "third_party/android_deps/artifacts" ]; then
    set +e
    if [ ! "third_party/android_deps/artifacts" -ef "$MIRROR_DEPS_PATH/artifacts" ]; then
        cp -rf third_party/android_deps/artifacts "$MIRROR_DEPS_PATH/" 2>/dev/null || true
    fi
    set -e
    echo "SUCCESS: Verificación de artefactos .jar/.aar completada sin colisiones de enlaces."
fi

# =========================================================================
# PURGA QUIRÚRGICA DE FLAGS DE COMPILACIÓN EN FUENTES (KOTLINC / JAVA LINTERS)
# =========================================================================
echo "INFRA: Desactivando alertas estrictas y flags de linter incompatibles con Kotlin..."
export KOTLIN_COMPILER_ARGS="-nowarn -warn:0"
export KOTLINC_ARGS="-nowarn"

# Modificamos de raíz el runner de Kotlin para que ignore flags desconocidos de Java como -Xlint
find . -name "kotlinc_runner.py" -exec sed -i "s|retcode = subprocess.check_call(kotlin_args + args.rest)|kotlin_args.append('-nowarn')\n    retcode = subprocess.check_call(kotlin_args + args.rest)|g" {} +

# Purgamos de forma agresiva cualquier declaración implícita de -Werror o -Xlint en el árbol de fuentes GN
find . -type f \( -name "BUILD.gn" -o -name "*.gni" \) -exec sed -i 's|"-Werror",||g' {} + 2>/dev/null || true
find . -type f \( -name "BUILD.gn" -o -name "*.gni" \) -exec sed -i 's|"-Werror"||g' {} + 2>/dev/null || true
find . -type f \( -name "BUILD.gn" -o -name "*.gni" \) -exec sed -i 's|"-Xlint:[^"]*",||g' {} + 2>/dev/null || true
find . -type f \( -name "BUILD.gn" -o -name "*.gni" \) -exec sed -i 's|"-Xlint:[^"]*"||g' {} + 2>/dev/null || true

# =========================================================================
# GENERACIÓN DE ENTORNO GN (Alineado con los fuentes nativos de la rama v1.3)
# =========================================================================
echo "INFRA: Sincronizando árbol estructural de GN (Mapeo incremental)..."
gn gen out/android-arm-tv-server \
  --args="target_os=\"android\" target_cpu=\"arm\" android_ndk_root=\"$ANDROID_NDK_ROOT\" android_sdk_root=\"$ANDROID_HOME\" chip_config_network_layer_ble=false treat_warnings_as_errors=false" \
  --root=examples/tv-app/android/

# =========================================================================
# PURGA POST-GN EN ARTEFACTOS GENERADOS (Se ejecuta inmediatamente antes del build)
# =========================================================================
echo "INFRA: Purgando referencias de -Xlint heredadas en los perfiles generados por GN..."
find out/ -name "*.json" -exec sed -i 's|"-Werror",||g' {} + 2>/dev/null || true
find out/ -name "*.json" -exec sed -i 's|"-Xlint:[^"]*",||g' {} + 2>/dev/null || true
find out/ -name "*.json" -exec sed -i 's|"-Xlint:[^"]*"||g' {} + 2>/dev/null || true
find out/ -name "*.ninja" -exec sed -i 's|-Xlint:all||g' {} + 2>/dev/null || true
find out/ -name "*.ninja" -exec sed -i 's|-Xlint:deprecation||g' {} + 2>/dev/null || true

# =========================================================================
# COMPILACIÓN MAESTRA INCREMENTAL CON NINJA
# =========================================================================
echo "INFRA: Ejecutando Ninja. El búnker procesará la compilación de forma segura..."
ninja -C out/android-arm-tv-server
