FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    debootstrap \
    squashfs-tools \
    xorriso \
    isolinux \
    syslinux-common \
    grub-pc-bin \
    mtools \
    dosfstools \
    rsync \
    wget \
    curl \
    git \
    --no-install-recommends && \
    apt-get clean

WORKDIR /build
VOLUME ["/build"]

CMD ["/bin/bash"]
