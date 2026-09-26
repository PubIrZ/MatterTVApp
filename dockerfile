# 1. Partimos de la imagen oficial estable de Project CHIP
FROM ghcr.io/project-chip/chip-build-android:126

USER root
WORKDIR /workspace

# 2. Descargamos el código fuente completo con submódulos de forma permanente dentro de la imagen
RUN git clone --depth 1 --branch v1.3-branch "https://github.com/project-chip/connectedhomeip.git" . \
    && git submodule update --init --recursive --depth 1

# 3. Configuramos la excepción de Git global de forma interna para que nunca más falle por permisos
RUN git config --global --add safe.directory /workspace

# Copiamos tu script de compilación dinámico dentro de la estructura nativa
COPY compilar_core.sh /workspace/compilar_core.sh
RUN chmod +x /workspace/compilar_core.sh
