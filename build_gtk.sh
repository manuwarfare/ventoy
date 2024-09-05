#!/bin/bash

set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required tools
for cmd in gcc pkg-config make; do
    if ! command_exists $cmd; then
        echo "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

# Get the target architecture
ARCH=${1:-$(dpkg-architecture -qDEB_HOST_ARCH)}

case $ARCH in
    amd64|x86_64)
        CC="gcc"
        LIBSUFFIX="64"
        TOOLDIR="x86_64"
        ;;
    i386)
        CC="gcc -m32"
        LIBSUFFIX="32"
        TOOLDIR="i386"
        ;;
    arm64|aarch64)
        if ! command_exists aarch64-linux-gnu-gcc; then
            echo "Error: aarch64-linux-gnu-gcc not found. Install gcc-aarch64-linux-gnu package."
            exit 1
        fi
        CC="aarch64-linux-gnu-gcc"
        LIBSUFFIX="aa64"
        TOOLDIR="aarch64"
        ;;
    mips64el)
        if ! command_exists mips64el-linux-gnuabi64-gcc; then
            echo "Error: mips64el-linux-gnuabi64-gcc not found. Install gcc-mips64el-linux-gnuabi64 package."
            exit 1
        fi
        CC="mips64el-linux-gnuabi64-gcc"
        LIBSUFFIX="m64e"
        TOOLDIR="mips64el"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Add hardening flags
HARDENING_CFLAGS="-fPIE -fstack-protector-strong -Wformat -Werror=format-security"
HARDENING_CPPFLAGS="-D_FORTIFY_SOURCE=2"
HARDENING_LDFLAGS="-Wl,-z,relro -Wl,-z,now"

# Function to build Ventoy
build_ventoy() {
    local gtkver="gtk3"

    echo "Building for $ARCH using $CC"

    # Get GTK flags
    GTKFLAGS=$(pkg-config --cflags --libs gtk+-3.0)

    # Build civetweb
    $CC $GTKFLAGS $HARDENING_CFLAGS $HARDENING_CPPFLAGS -c -Wall -Wextra -Wshadow -Wformat-security -Winit-self \
        -Wmissing-prototypes -O2 -DLINUX \
        -I./Ventoy2Disk/Lib/libhttp/include \
        -DNDEBUG -DNO_CGI -DNO_CACHING -DNO_SSL -DSQLITE_DISABLE_LFS -DSSL_ALREADY_INITIALIZED \
        -DUSE_STACK_SIZE=102400 -DNDEBUG -fPIC \
        ./Ventoy2Disk/Lib/libhttp/include/civetweb.c \
        -o ./civetweb.o

    # Build Ventoy2Disk
    $CC -O2 -Wall -Wno-unused-function -DSTATIC=static -DINIT= \
        $HARDENING_CFLAGS $HARDENING_CPPFLAGS \
        -I./Ventoy2Disk \
        -I./Ventoy2Disk/Core \
        -I./Ventoy2Disk/Web \
        -I./Ventoy2Disk/GTK \
        -I./Ventoy2Disk/Include \
        -I./Ventoy2Disk/Lib/libhttp/include \
        -I./Ventoy2Disk/Lib/fat_io_lib/include \
        -I./Ventoy2Disk/Lib/xz-embedded/linux/include \
        -I./Ventoy2Disk/Lib/xz-embedded/linux/include/linux \
        -I./Ventoy2Disk/Lib/xz-embedded/userspace \
        -I./Ventoy2Disk/Lib/exfat/src/libexfat \
        -I./Ventoy2Disk/Lib/exfat/src/mkfs \
        -I./Ventoy2Disk/Lib/fat_io_lib \
        -L./Ventoy2Disk/Lib/fat_io_lib/lib \
        Ventoy2Disk/main_gtk.c \
        Ventoy2Disk/Core/*.c \
        Ventoy2Disk/Web/*.c \
        Ventoy2Disk/GTK/*.c \
        Ventoy2Disk/Lib/xz-embedded/linux/lib/decompress_unxz.c \
        Ventoy2Disk/Lib/exfat/src/libexfat/*.c \
        Ventoy2Disk/Lib/exfat/src/mkfs/*.c \
        Ventoy2Disk/Lib/fat_io_lib/*.c \
        -l pthread \
        ./civetweb.o \
        $HARDENING_LDFLAGS \
        -o Ventoy2Disk.${gtkver}_$LIBSUFFIX $GTKFLAGS

    # Build VentoyGUI
    $CC -O2 -D_FILE_OFFSET_BITS=64 $HARDENING_CFLAGS $HARDENING_CPPFLAGS \
        Ventoy2Disk/ventoy_gui.c Ventoy2Disk/Core/ventoy_json.c \
        -I Ventoy2Disk/Core -DVTOY_GUI_ARCH="\"$TOOLDIR\"" \
        $HARDENING_LDFLAGS \
        -o VentoyGUI.$TOOLDIR $GTKFLAGS

    # Strip binaries
    strip Ventoy2Disk.${gtkver}_$LIBSUFFIX VentoyGUI.$TOOLDIR

    # Rename and move binaries
    if [ -e Ventoy2Disk.${gtkver}_$LIBSUFFIX ]; then
        mv Ventoy2Disk.${gtkver}_$LIBSUFFIX Ventoy2Disk.${gtkver}
        mkdir -p tool/$TOOLDIR
        cp Ventoy2Disk.${gtkver} tool/$TOOLDIR/
        rm Ventoy2Disk.${gtkver}
    fi

    # Rename VentoyGUI binary to 'ventoy'
    if [ -e VentoyGUI.$TOOLDIR ]; then
        mv VentoyGUI.$TOOLDIR ventoygui
    fi

    # Clean up
    echo "Build completed successfully."
}

# Main execution
build_ventoy