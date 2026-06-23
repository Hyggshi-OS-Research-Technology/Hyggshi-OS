# Hyggshi OS

A custom Debian-based Linux distribution with KDE Plasma desktop.

## Build Requirements
- Docker
- ~5GB free disk space

## Build

```bash
docker build -t hyggshi-os-builder .
cp build.sh build/
docker run --rm -it --privileged \
    -v $(pwd)/build:/build \
    hyggshi-os-builder \
    bash /build/build.sh
```

## Stack
- Base: Debian Bookworm
- Desktop: KDE Plasma 5.27
- Display Manager: SDDM
- Bootloader: isolinux (BIOS)

## Links
- Website: https://hyggshi-os-website.pages.dev
