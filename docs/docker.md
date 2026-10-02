# Docker setup

Use a container instead of installing the toolchain by hand ([setup.md](setup.md)
step 1). Supported hosts:

- **x86_64 Linux**
- **Apple Silicon macOS** (Docker Desktop; the image runs natively as `linux/arm64`)

The image holds only tools. The repo is bind-mounted at `/pitorch`, so build output
lands in your working tree, owned by your user.

| Tool | Notes |
|---|---|
| `arm-none-eabi-gcc` 10.3-2021.10 | ARM's x86_64 or aarch64 Linux build, chosen automatically |
| `vc4asm`, `vc4dis` | QPU assembler, built from [maazl/vc4asm](https://github.com/maazl/vc4asm) |
| `my-install` | Linux build of the UART loader, at `/usr/local/bin/my-install` |
| `python3` | `sentencepiece`, `numpy`; `torch` is optional (see below) |

## Quick start

```bash
git clone https://github.com/masonjwang/pitorch.git && cd pitorch
docker/pitorch.sh --build                               # build the image (a few minutes, once)
docker/pitorch.sh make -C libpi                         # step 2: support library
docker/pitorch.sh make -C tools/bootloader kernel.img   # step 2: Pi-side bootloader
```

Steps 3–4 (SD card, weights) are mostly the same as in [setup.md](setup.md); see
[Weights and SD card](#weights-and-sd-card). For step 5, see
[Running on the Pi](#running-on-the-pi).

## The `docker/pitorch.sh` wrapper

```bash
docker/pitorch.sh                  # interactive shell in /pitorch
docker/pitorch.sh <cmd> [args...]  # run one command
docker/pitorch.sh --build [cmd]    # rebuild the image first (e.g. after editing the Dockerfile)
```

The wrapper:
- Builds the image on first use if it doesn't exist.
- Mounts the repo at `/pitorch` and runs as your UID/GID.
- Forwards `PI_DEVICE` and `PI_PORT` when they're set.
- On Linux only, passes through every `/dev/ttyUSB*` and `/dev/ttyACM*`, along with each
  device's group, so you don't need `dialout` inside the container. Plug in the adapter
  **before** starting the container.

Set `PITORCH_IMAGE` to use a different image tag. Without the wrapper, the equivalent is:

```bash
docker build -t pitorch -f docker/Dockerfile .
docker run --rm -it -v "$PWD:/pitorch" --user "$(id -u):$(id -g)" \
    --device /dev/ttyUSB0 --group-add "$(stat -c %g /dev/ttyUSB0)" pitorch
```

### Build options

| Build arg | Default | |
|---|---|---|
| `WITH_TORCH` | `0` | `1` adds CPU PyTorch (only needed for `dev/host/reference.py`) |
| `VC4ASM_REF` | `master` | vc4asm commit or tag to build |
| `ARM_GCC_VERSION` | `10.3-2021.10` | ARM GNU toolchain release |

```bash
docker build -t pitorch -f docker/Dockerfile --build-arg WITH_TORCH=1 .
```

## Build only `kernel.img` in the container

Don't run plain `make -C tools/bootloader` in the container. It also rebuilds
`tools/bootloader/unix-side/my-install`, which is a committed macOS binary, and
the container would overwrite it with a Linux one. The image already has a
Linux `my-install`, and `examples/run.sh` uses it through `PI_BOOTLOADER`.

## Weights and SD card

Download and convert in the container:

```bash
docker/pitorch.sh bash tools/download.sh 15M tokenizer
docker/pitorch.sh python3 dev/host/export_tokenizer.py \
    --tokenizer-model tools/tokenizer.model --output tools/tokenizer.bin
```

Copying to the SD card happens on the host, where the card is mounted.
`tools/scripts/setup-sd.sh` is macOS-only (it looks under `/Volumes`). On Linux,
follow what it does by hand:

```bash
SD=/media/$USER/<YOUR_SD>
cp tools/sdcard/* "$SD"/
mkdir -p "$SD/weights"
cat tools/stories15M.bin tools/tokenizer.bin > "$SD/weights/stories15M_full.bin"
echo "initramfs weights/stories15M_full.bin 0x2000000" >> "$SD/config.txt"
```

## Running on the Pi

`examples/run.sh` assembles the QPU shaders, builds the examples, and then uploads
the `.bin` over UART.

### Linux: everything in the container

```bash
PI_PORT=/dev/ttyUSB0 docker/pitorch.sh bash -c 'cd examples && ./run.sh generate'
```

`PI_PORT` overrides the macOS `/dev/cu.usbserial-*` names from `devices.conf`. It
applies to the single-Pi demos (`generate`, `train`). The distributed demos still
read their ports from `devices.conf`.

### macOS: build in the container, upload from the host

Docker Desktop can't pass USB serial devices into containers. Build in the
container, then upload with the committed macOS loader:

```bash
docker/pitorch.sh bash -c 'cd examples && ./run.sh generate'
# builds examples/generate.bin, then stops with
# "couldn't open tty port" because the container can't see the Pi; that's expected

tools/bin/my-install /dev/cu.usbserial-1330 examples/generate.bin
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `couldn't open tty port </dev/cu.usbserial-…>` on Linux | Set `PI_PORT=/dev/ttyUSB0` (or `ttyACM0`). |
| `couldn't open tty port </dev/ttyUSB0>` | The adapter was plugged in after the container started. Restart the command. |
| `vc4asm: Failed to open …/vc4tmpl/template.h` | The image is out of date. Run `docker/pitorch.sh --build`. |
| `exec format error` on Apple Silicon | The image was built for the wrong platform. Rebuild on the Mac, or pass `--platform linux/arm64`. |
| `tools/bin/my-install` became a Linux binary | `git checkout tools/bin/my-install tools/bootloader/unix-side/my-install` |
