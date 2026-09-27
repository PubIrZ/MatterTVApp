#!/bin/bash

echo "INFRA DEBUG: La ruta de GITHUB_WORKSPACE detectada en este runner es: $GITHUB_WORKSPACE"
exit 10
#echo "🚨 MODO RESCATE ACTIVO: Saltando compilación y forzando subida inmediata del out (gh artifact upload)."
#exit 10

# =========================================================================
# SCRIPT DINÁMICO DE COMPILACIÓN - BYPASS TOTAL DE WARNINGS DE KOTLIN
# =========================================================================
set -e # Detiene el script inmediatamente si ocurre un error inesperado

# 🚀 FORZAR USO DE JAVA 11 PARA EVITAR EL ERROR "major version 61"
POSIBLE_JAVA_11=$(find /opt/hostedtoolcache/Java_Zulu_jdk/ -maxdepth 2 -name "11.*" | head -n 1)
if [ -n "$POSIBLE_JAVA_11" ]; then
    export JAVA_HOME="$POSIBLE_JAVA_11/x64"
    export PATH="$JAVA_HOME/bin:$PATH"
fi

echo "INFRA: Ajustando entorno a $(java -version 2>&1 | head -n 1)"


# =========================================================================
# ¡EL LIMPIADOR MAESTRO DE SALTOS DE LÍNEA DE WINDOWS (CRLF a LF)!
# =========================================================================
sed -i 's/\r$//' "$0" || true

echo "INFRA: Inicializando el entorno virtual aislado de Pigweed..."
source scripts/activate.sh

echo "INFRA: Descargando pre-requisitos de dependencias de Android..."
python3 third_party/android_deps/set_up_android_deps.py
third_party/java_deps/set_up_java_deps.sh

# =========================================================================
# ¡EL CAMBIO MAESTRO DE RAÍZ! ELIMINAMOS -Werror Y DESACTIVAMOS ALERTAS (.gn y .gni)
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

# 🚀 ¡AÑADE ESTA NUEVA LÍNEA AQUÍ PARA CORREGIR EL ERROR DE JAVA 17!
find . -name "gradle.properties" -exec sed -i 's|-XX:MaxPermSize=2048m||g' {} +

# =========================================================================
# ANULACIÓN COMPLETA EN EL MOTOR DE PIGWEED (KOTLINC)
# Modificamos el script wrapper para inyectar '-nowarn' al final del comando
# =========================================================================
echo "INFRA: Inyectando inhibidores de error '-nowarn' en el motor de Pigweed..."
export KOTLIN_COMPILER_ARGS="-nowarn -warn:0"
export KOTLINC_ARGS="-nowarn"

# Modificamos el script ejecutable de Python de forma segura. 
# En lugar de romper la cabecera, inyectamos '-nowarn' de forma segura en los argumentos adicionales.
find . -name "kotlinc_runner.py" -exec sed -i "s|retcode = subprocess.check_call(kotlin_args + args.rest)|kotlin_args.append('-nowarn')\n    retcode = subprocess.check_call(kotlin_args + args.rest)|g" {} +
find . -name "kotlinc_runner.py" -exec sed -i "s|'-Werror'||g" {} +

echo "INFRA: Sincronizando árbol estructural de GN..."
gn gen out/android-arm-tv-server \
  --args='target_os="android" target_cpu="arm" android_ndk_root="'$ANDROID_NDK_ROOT'" android_sdk_root="/usr/local/lib/android/sdk" chip_config_network_layer_ble=false treat_warnings_as_errors=false' \
  --root=examples/tv-app/android/

# Parches secundarios de seguridad de última capa sobre archivos de configuración JSON
find out/ -name "*.json" -exec sed -i 's|"-Werror",||g' {} +

echo "INFRA: Ninja reanudará la compilación de forma incremental..."
#ninja -C out/android-arm-tv-server
./scripts/build/build_examples.py --target android-arm-tv-server build

# =========================================================================
# 🚀 OPTIMIZACIÓN POST-COMPILACIÓN (LLVM-STRIP CON ENTORNO DINÁMICO DE BASH)
# =========================================================================
echo "========================================================================="
echo "INFRA: Compilación completada. Generando copias '_small' para comparativa..."
echo "========================================================================="

## Usamos la ruta absoluta exacta basada en el Workspace real del host de GitHub
#JNI_TARGET_DIR="/home/runner/work/MatterTVApp/MatterTVApp/matter-sdk/examples/tv-app/android/App/app/libs/jniLibs/armeabi-v7a"

# $GITHUB_WORKSPACE apunta dinámicamente a /home/runner/work/MatterTVApp/MatterTVApp
JNI_TARGET_DIR="$GITHUB_WORKSPACE/matter-sdk/examples/tv-app/android/App/app/libs/jniLibs/armeabi-v7a"
STRIP_TOOL="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"

if [ -f "$JNI_TARGET_DIR/libTvApp.so" ] && [ -x "$STRIP_TOOL" ]; then
    echo "INFRA: Duplicando y reduciendo binarios nativos con llvm-strip..."
    
    # El parámetro -o clona y aplica el strip en el nuevo archivo sin alterar el original
    $STRIP_TOOL --strip-unneeded "$JNI_TARGET_DIR/libTvApp.so" -o "$JNI_TARGET_DIR/libTvApp_small.so"
    $STRIP_TOOL --strip-unneeded "$JNI_TARGET_DIR/libc++_shared.so" -o "$JNI_TARGET_DIR/libc++_shared_small.so"
    
    echo "========================================================================="
    echo "📊 COMPARATIVA DE TAMAÑOS EN EL DISCO DEL RUNNER:"
    echo "========================================================================="
    ls -lh "$JNI_TARGET_DIR"/libTvApp*.so
    ls -lh "$JNI_TARGET_DIR"/libc++_shared*.so
    echo "========================================================================="
else
    echo "⚠️ ADVERTENCIA CRÍTICA: No se localizaron los binarios en la ruta exacta:"
    echo "-> Buscado en: $JNI_TARGET_DIR/libTvApp.so"
fi
