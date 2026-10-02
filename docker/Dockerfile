# PiTorch build environment: everything from docs/setup.md step 1 on Linux.
# Multi-arch: builds natively on x86_64 Linux and on Apple Silicon (linux/arm64).
#   - arm-none-eabi-gcc 10.3-2021.10 (bare-metal ARM cross-compiler)
#   - vc4asm (QPU assembler, built from source)
#   - my-install (UART loader) built for Linux, at /usr/local/bin/my-install
#   - host cc, python3 + sentencepiece/numpy (tokenizer export, sharding)
#
# Build:  docker build -t pitorch -f docker/Dockerfile .
# Use:    see docs/docker.md
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG ARM_GCC_VERSION=10.3-2021.10
ARG VC4ASM_REF=master
# Set to 1 to also install CPU PyTorch (only needed for dev/host/reference.py).
ARG WITH_TORCH=0

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git curl ca-certificates bzip2 xz-utils \
        python3 python3-pip \
        libncurses5 \
    && rm -rf /var/lib/apt/lists/*

# ── ARM cross-compiler ──
RUN set -eux; \
    case "$(uname -m)" in \
        x86_64)  host=x86_64 ;; \
        aarch64) host=aarch64 ;; \
        *) echo "unsupported arch $(uname -m)"; exit 1 ;; \
    esac; \
    curl -fsSL "https://developer.arm.com/-/media/Files/downloads/gnu-rm/${ARM_GCC_VERSION}/gcc-arm-none-eabi-${ARM_GCC_VERSION}-${host}-linux.tar.bz2" \
        | tar -xj -C /opt; \
    ln -s "/opt/gcc-arm-none-eabi-${ARM_GCC_VERSION}" /opt/gcc-arm-none-eabi
ENV PATH=/opt/gcc-arm-none-eabi/bin:$PATH

# ── vc4asm (QPU assembler) ──
RUN set -eux; \
    git clone https://github.com/maazl/vc4asm.git /tmp/vc4asm; \
    cd /tmp/vc4asm && git checkout "$VC4ASM_REF"; \
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release; \
    cmake --build build -j"$(nproc)" --target vc4asm vc4dis; \
    install -m 755 build/vc4asm build/vc4dis /usr/local/bin/; \
    mkdir -p /usr/local/share && cp -r share/vc4inc share/vc4tmpl /usr/local/share/; \
    rm -rf /tmp/vc4asm

# ── Python deps ──
RUN pip3 install --no-cache-dir sentencepiece numpy \
    && if [ "$WITH_TORCH" = "1" ]; then \
         pip3 install --no-cache-dir torch --index-url https://download.pytorch.org/whl/cpu; \
       fi

# ── my-install (host-side UART loader), Linux build ──
# Built here rather than in the repo: tools/bin/my-install and
# tools/bootloader/unix-side/my-install are committed macOS binaries.
COPY tools/bootloader/unix-side /tmp/boot/unix-side
COPY tools/bootloader/pi-side/boot-defs.h tools/bootloader/pi-side/boot-crc32.h /tmp/boot/pi-side/
RUN make -C /tmp/boot/unix-side clean my-install \
    && install -m 755 /tmp/boot/unix-side/my-install /usr/local/bin/my-install \
    && rm -rf /tmp/boot
# examples/run.sh uses this instead of tools/bin/my-install.
ENV PI_BOOTLOADER=/usr/local/bin/my-install

# The repo is bind-mounted here at runtime.
WORKDIR /pitorch
# Lets a non-root --user write files without a home dir warning.
ENV HOME=/tmp

CMD ["bash"]
