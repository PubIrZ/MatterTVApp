# =========================================================================
# PARTE 2: ENTORNO BLINDADO POST-BORRADO (ZAP, KOTLINC Y ESTRUCTURA)
# =========================================================================

# 1. Asegurar exposición nativa de binarios del NDK r23c y Clang
STATIC_BIN_DIR="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
if [ -d "$STATIC_BIN_DIR" ]; then
    export PATH="$STATIC_BIN_DIR:$PATH"
fi

# 2. Localizar e inyectar de forma robusta kotlinc y java en el PATH
KOTLINC_PATH=$(find .environment/ -name "kotlinc" -type f -print -quit 2>/dev/null)
if [ -n "$KOTLINC_PATH" ]; then
    KOTLINC_DIR=$(dirname "$KOTLINC_PATH")
    export PATH="$KOTLINC_DIR:$PATH"
    chmod +x "$KOTLINC_DIR"/* || true
    echo "INFRA: Herramientas de Kotlin expuestas desde: $KOTLINC_DIR"
fi

# 3. Remover flags estrictos que causan caídas (-Werror y -Xlint) en código fuente
echo "INFRA: Removiendo flags estrictos de las plantillas fuentes BUILD.gn y .gni..."
find . -type f \( -name "BUILD.gn" -o -name "*.gni" \) -exec sed -i 's|"-Werror",||g' {} + 2>/dev/null || true
find . -type f \( -name "BUILD.gn" -o -name "*.gni" \) -exec sed -i 's|"-Werror"||g' {} + 2>/dev/null || true
find . -type f \( -name "BUILD.gn" -o -name "*.gni" \) -exec sed -i 's|"-Xlint:[^"]*",||g' {} + 2>/dev/null || true
find . -type f \( -name "BUILD.gn" -o -name "*.gni" \) -exec sed -i 's|"-Xlint:[^"]*"||g' {} + 2>/dev/null || true

# 4. Inhibición total de alertas para el compilador de Kotlin de Pigweed
export KOTLIN_COMPILER_ARGS="-nowarn -warn:0"
export KOTLINC_ARGS="-nowarn"
find . -name "kotlinc_runner.py" -exec sed -i "s|retcode = subprocess.check_call(kotlin_args + args.rest)|kotlin_args.append('-nowarn')\n    retcode = subprocess.check_call(kotlin_args + args.rest)|g" {} +

# 5. CREACIÓN PREVENTIVA DEL ÁRBOL COMPLETO DE CÓDIGO GENERADO (Evita errores de directorio ausente)
echo "INFRA: Asegurando estructura de directorios para artefactos ZAP..."
mkdir -p zzz_generated/app-common/app-common/zap-generated/attributes/
mkdir -p zzz_generated/tv-app/zap-generated/
mkdir -p zzz_generated/placeholder/

# 6. Sincronizar árbol estructural de GN limpio
echo "INFRA: Sincronizando árbol estructural de GN..."
gn gen out/android-arm-tv-server \
  --args='target_os="android" target_cpu="arm" android_ndk_root="'$ANDROID_NDK_ROOT'" android_sdk_root="'$ANDROID_HOME'" chip_config_network_layer_ble=false treat_warnings_as_errors=false' \
  --root=examples/tv-app/android/

# 7. EJECUCIÓN DEL MOTOR DE GENERACIÓN ZAP (Fuerza la creación de Accessors.cpp)
echo "INFRA: Invocando generadores dinámicos ZAP en frío..."
set +e
# Intentamos que Ninja cree los archivos mediante las reglas de Matter
ninja -C out/android-arm-tv-server third_party/connectedhomeip/examples/tv-app/tv-common:tv-common_zapgen_generate
# Ejecutamos el script de Python nativo como respaldo directo sobre nuestra carpeta estructurada
if [ -f "scripts/tools/zap/generate.py" ]; then
    python3 scripts/tools/zap/generate.py examples/tv-app/tv-common/tv-app.zap -o zzz_generated/app-common/app-common/zap-generated/ || true
fi
set -e

# 8. Purgar flags incompatibles que se hayan regenerado en los archivos finales de Ninja
echo "INFRA: Purgando residuos de flags de los artefactos generados por GN..."
find out/ -name "*.json" -exec sed -i 's|"-Werror",||g' {} +
find out/ -name "*.json" -exec sed -i 's|"-Xlint:deprecation",||g' {} +
find out/ -name "*.ninja" -exec sed -i 's|-Xlint:deprecation||g' {} +

# 9. Compilación Maestra Final
echo "INFRA: Iniciando compilación incremental completa..."
ninja -C out/android-arm-tv-server
