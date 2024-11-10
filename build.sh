#!/bin/bash

# Load configuration file
source "$(pwd)/config.sh"

# File name where the API key should be located
API_KEY_FILE="$(pwd)/openai_api_key.txt"

# Logging function for easier tracking of script progress and errors
log() {
    local message="$1"
    echo "$message"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
}

# Function to load the GPT API key if the file exists
load_api_key() {
    if [ -f "$API_KEY_FILE" ]; then
        api_key=$(<"$API_KEY_FILE")
        log "OpenAI API key loaded from $API_KEY_FILE."
    else
        log "No OpenAI API key file found. GPT error explanations will be disabled."
        api_key=""
    fi
}

# Function to query the GPT API for error explanations, if the key exists
explain_error() {
    local error_message="$1"
    
    # Check if the API key is loaded
    if [ -z "$api_key" ]; then
        log "API key not found. Skipping GPT error explanation."
        return
    fi

    # Make the GPT API request to get the error explanation
    response=$(curl -s -X POST "https://api.openai.com/v1/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $api_key" \
        -d '{
            "model": "text-davinci-003",
            "prompt": "Explain this Linux shell error: '"$error_message"'",
            "max_tokens": 50,
            "temperature": 0.5
        }')
    
    # Extract the explanation from the API response and display it
    explanation=$(echo "$response" | jq -r '.choices[0].text')
    echo -e "\nGPT Explanation:\n$explanation"
    log "GPT Explanation for error '$error_message': $explanation"
}

# Function to handle errors and request explanation, if available
handle_error() {
    local error_message="$1"
    log "Error encountered: $error_message"
    explain_error "$error_message"
}

# Function to check if required tools and directories are available
check_requirements() {
    local tools=("make" "zip")
    local dirs=("$AK3_PATH" "$CDIR/toolchain" "$CDIR/AIK")

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            handle_error "Required tool '$tool' not found."
            exit 1
        fi
    done

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            handle_error "Required directory '$dir' not found."
            exit 1
        fi
    done
    log "All required tools and directories are available."
}

# Function to validate the device codename
validate_codename() {
    while true; do
        echo "Enter the device codename (${VALID_CODENAMES[*]}):"
        read -r DEVICE_CODENAME

        if [[ " ${VALID_CODENAMES[*]} " =~ " ${DEVICE_CODENAME} " ]]; then
            log "Codename '${DEVICE_CODENAME}' validated."
            break
        else
            echo "Invalid codename. Please try again."
        fi
    done
}

# Function to confirm if the user wants to proceed with the compilation
confirm_compile() {
    while true; do
        echo "Do you want to proceed with the compilation? (y/n):"
        read -r CONFIRMATION
        case "$CONFIRMATION" in
            [Yy]* ) log "User confirmed to proceed with compilation."; break ;;
            [Nn]* ) log "User canceled the compilation."; echo "Compilation canceled."; exit 0 ;;
            * ) echo "Invalid response. Enter 'y' to continue or 'n' to cancel." ;;
        esac
    done
}

# Function to create the required directories
create_directories() {
    mkdir -p "$OUT_DIR" images builds || { handle_error "Error creating directories."; exit 1; }
    export CDIR="$(pwd)"
    log "Directories created."
}

# Function to clean up temporary directories and files
cleanup() {
    log "Starting cleanup..."
    rm -rf "$OUT_DIR" images
    log "Temporary files cleaned up."
}

# Function to measure and display the total execution time
measure_time() {
    local start_time="$1"
    local end_time=$(date +"%s")
    local diff=$((end_time - start_time))
    log "Total time: $((diff / 60)) minute(s) and $((diff % 60)) seconds."
}

# Main kernel compilation function
compile_kernel() {
    DEFCONFIG_NAME="exynos9830-${DEVICE_CODENAME}_defconfig"
    make O="$OUT_DIR" "$DEFCONFIG_NAME" || { handle_error "Kernel compilation failed at defconfig stage."; exit 1; }
    make O="$OUT_DIR" -j12 2>&1 | tee -a "$LOG_FILE" || { handle_error "Kernel compilation failed at make stage."; exit 1; }

    if [ ! -f "$OUT_DIR/arch/arm64/boot/Image" ]; then
        handle_error "Compilation failed. Kernel image not found."
        exit 1
    else
        log "Kernel compiled successfully."
    fi
}

# Function to generate the AnyKernel3 package
generate_anykernel_zip() {
    log "Generating AnyKernel3 zip..."
    rm -f "$AK3_PATH"/*.zip
    (cd "$AK3_PATH" && zip -r9 "$KERNELZIP" .) || { handle_error "Error creating AnyKernel package."; exit 1; }
    mv "$AK3_PATH/$KERNELZIP" "$CDIR/builds/${IMAGE_NAME}${KERNELVERSION}.zip"
    log "AnyKernel3 zip generated."
}

# Function to generate the flashable image
generate_flashable_image() {
    log "Generating flashable image..."
    cd "$CDIR/AIK"
    ./cleanup.sh
    ./unpackimg.sh --nosudo

    mv "$AK3_PATH/dtb.img" "$CDIR/images/boot.img-dtb"
    mv "$OUT_DIR/arch/arm64/boot/Image" "$CDIR/images/boot.img-kernel"

    rm -f "$CDIR/AIK/split_img/boot.img-kernel" "$CDIR/AIK/split_img/boot.img-dtb"
    mv "$CDIR/images/boot.img-kernel" "$CDIR/AIK/split_img/"
    mv "$CDIR/images/boot.img-dtb" "$CDIR/AIK/split_img/"
    ./repackimg.sh --nosudo

    mv "$CDIR/AIK/image-new.img" "$CDIR/builds/${IMAGE_NAME}.img"
    log "Flashable image generated."
}

# Load the API key before starting the process
load_api_key

# Execution starts here
DATE_START=$(date +"%s")

log "Starting build process..."
check_requirements
validate_codename
confirm_compile
create_directories

compile_kernel
generate_anykernel_zip
generate_flashable_image

cleanup
measure_time "$DATE_START"

log "Build process completed. Find your zip and image in the 'builds' directory."

