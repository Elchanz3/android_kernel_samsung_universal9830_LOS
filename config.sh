# Configuration file for kernel build script

# List of valid device codenames
VALID_CODENAMES=("c1sxxx" "x1slte" "x1sxxx" "y2sxxx" "z3sxxx")

# Paths for output, logging, and AnyKernel3
OUT_DIR="$HOME/Documentos/GitHub/android_kernel_samsung_universal9830_LOS/kout"
AK3_PATH="$HOME/Documentos/GitHub/android_kernel_samsung_universal9830_LOS/AnyKernel3"
CDIR="$(pwd)"
LOG_FILE="smartaxx.log"

# Kernel image name and version
IMAGE_NAME="SmartaxxKernel"
KERNELZIP="SmartaxxKernel.zip"
KERNELVERSION="0.1"

# Build parameters
PLATFORM_VERSION="11"
ANDROID_MAJOR_VERSION="r"
ARCH="arm64"
SEC_BUILD_CONF_VENDOR_BUILD_OS="13"

echo "configuration done"
