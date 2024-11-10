#!/bin/bash

# Load configuration file
source "$(pwd)/config.sh"

# Function to validate the device codename
validate_codename() {
    while true; do
        echo "Enter the device codename (${VALID_CODENAMES[*]}):"
        read -r DEVICE_CODENAME

        # Check if the codename is in the list of valid codenames
        if [[ " ${VALID_CODENAMES[*]} " =~ " ${DEVICE_CODENAME} " ]]; then
            echo "Codename '${DEVICE_CODENAME}' validated."
            break
        else
            echo "Invalid codename. Please try again."
        fi
    done
}

# Function to confirm whether the user wants to proceed with the compilation
confirm_compile() {
    while true; do
        echo "Do you want to proceed with the compilation? (y/n):"
        read -r CONFIRMATION
        case "$CONFIRMATION" in
            [Yy]* ) echo "$(date): User confirmed to proceed with compilation." >> "$LOG_FILE"; break ;; # Log confirmation
            [Nn]* ) echo "$(date): User canceled the compilation." >> "$LOG_FILE"; echo "Compilation canceled."; exit 0 ;; # Log cancellation
            * ) echo "Invalid response. Enter 'y' to continue or 'n' to cancel." ;;
        esac
    done
}

# Run codename validation and confirmation before starting the compilation
validate_codename
confirm_compile

# Define the defconfig name based on the codename
DEFCONFIG_NAME="exynos9830-${DEVICE_CODENAME}_defconfig"
SEC_CONFIG="smartaxx_defconfig"

# Create necessary directories with -p to avoid errors if they already exist
mkdir -p "$OUT_DIR" images builds
export CDIR="$(pwd)"

DATE_START=$(date +"%s")

# Compile the kernel using the generated defconfig name
make O="$OUT_DIR" "$SEC_CONFIG" "$DEFCONFIG_NAME"
make O="$OUT_DIR" -j12 2>&1 | tee "$LOG_FILE"

# Generate device tree blobs
cd "$CDIR/toolchain"
./mkdtimg cfg_create "$AK3_PATH/dtb.img" "$CDIR/dtconfigs/exynos9830.cfg" -d "$OUT_DIR/arch/arm64/boot/dts/exynos"
./mkdtimg cfg_create "$AK3_PATH/dtbo.img" "$CDIR/dtconfigs/c1s.cfg" -d "$OUT_DIR/arch/arm64/boot/dts/samsung"

# Copy the kernel image
cp "$OUT_DIR/arch/arm64/boot/Image" "$AK3_PATH/Image"
export IMAGE="$AK3_PATH/Image"

echo "******************************************"
echo "Checking required files..."
echo "******************************************"

# Check if the compiled image exists
if [ ! -f "$IMAGE" ]; then
    echo "Compilation failed. File '$IMAGE' not found. Check logs."
    exit 1
else
    echo "File '$IMAGE' found. Proceeding to the next step."
fi

echo "******************************************"
echo "Generating AnyKernel3 zip..."
echo "******************************************"

# Remove old zip files and create a new kernel package
rm -f "$AK3_PATH"/*.zip
(cd "$AK3_PATH" && zip -r9 "$KERNELZIP" .) || { echo "Error creating AnyKernel package"; exit 1; }
mv "$AK3_PATH/$KERNELZIP" "$CDIR/builds/${IMAGE_NAME}${KERNELVERSION}.zip"
echo "Zip completed..."

echo "******************************************"
echo "Generating flashable image..."
echo "******************************************"

# Clean up and repack the image
cd "$CDIR/AIK"
./cleanup.sh
./unpackimg.sh --nosudo

# Move generated files to a temporary directory
mv "$AK3_PATH/dtb.img" "$CDIR/images/boot.img-dtb"
mv "$IMAGE" "$CDIR/images/boot.img-kernel"

# Update AIK with the new kernel and dtb images
rm -f "$CDIR/AIK/split_img/boot.img-kernel" "$CDIR/AIK/split_img/boot.img-dtb"
mv "$CDIR/images/boot.img-kernel" "$CDIR/AIK/split_img/"
mv "$CDIR/images/boot.img-dtb" "$CDIR/AIK/split_img/"

# Repack the boot image without sudo
rm -rf "$CDIR/images"
cd "$CDIR/AIK"
./repackimg.sh --nosudo

# Move the repacked image to the builds directory
cd "$CDIR"
mv "$CDIR/AIK/image-new.img" "$CDIR/builds/${IMAGE_NAME}.img"

# Remove the kout directory after build
if [ -d "$OUT_DIR" ]; then
    rm -rf "$OUT_DIR"
    echo "Directory 'kout' removed."
else
    echo "No 'kout' directory found."
fi

echo "Image generation completed."

DATE_END=$(date +"%s")
DIFF=$((DATE_END - DATE_START))

echo -e "\nTotal time: $((DIFF / 60)) minute(s) and $((DIFF % 60)) seconds.\n"
echo "Find your zip and image in the 'builds' directory."
