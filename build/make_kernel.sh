#!/bin/bash
# Script to build the Yoga Book kernel

echo "Building Yoga Book YB1-91F kernel..."

KERNEL_DIR="kernel/lenovo/yogabook"
OUTPUT_DIR="out/target/product/yogabook/obj/KERNEL_OBJ"

# Check if kernel directory exists
if [ ! -d "$KERNEL_DIR" ]; then
    echo "Error: Kernel directory not found at $KERNEL_DIR"
    echo "Please run repo sync first"
    exit 1
fi

cd "$KERNEL_DIR"

# Load yoga book defconfig if it exists
if [ -f "../../device/lenovo/yogabook/yogabook_defconfig" ]; then
    echo "Using Yoga Book defconfig..."
    make ARCH=arm64 yogabook_defconfig
else
    echo "Warning: yogabook_defconfig not found, using default defconfig"
    make ARCH=arm64 defconfig
fi

# Show kernel configuration menu (optional)
# make ARCH=arm64 menuconfig

# Build the kernel
echo "Building kernel..."
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image.gz dtbs

if [ $? -ne 0 ]; then
    echo "Error: Kernel build failed"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Copy kernel image and dtbs to output directory
echo "Copying kernel images to output directory..."
cp arch/arm64/boot/Image.gz "$OUTPUT_DIR/"
cp arch/arm64/boot/dts/*/*.dtb "$OUTPUT_DIR/" 2>/dev/null || true

echo "Kernel build complete!"
echo "Kernel image: $OUTPUT_DIR/Image.gz"
echo "DTB files: $OUTPUT_DIR/*.dtb"

# Optionally build modules
read -p "Build kernel modules? (y/N): " build_modules
if [[ "$build_modules" =~ ^[Yy]$ ]]; then
    echo "Building kernel modules..."
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_install INSTALL_MOD_PATH="$OUTPUT_DIR/modules"
    echo "Modules installed to: $OUTPUT_DIR/modules"
fi