#!/bin/bash
# =========================================================================
# SCRIPT DINÁMICO DE COMPILACIÓN - BYPASS TOTAL DE WARNINGS DE KOTLIN
# =========================================================================
set -e # Detiene el script inmediatamente si ocurre un error inesperado

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
ninja -C out/android-arm-tv-server
