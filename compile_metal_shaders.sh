#!/bin/bash

# MTTransitions Metal Shader Precompilation Script
# Compiles all .metal files to .metallib for SPM compatibility

set -e

# Configuration
METAL_SOURCE_DIR="./Source/Transitions"
OUTPUT_DIR="./Source/Resources/Shaders"
TEMP_DIR="./temp_air_files"
IOS_MIN_VERSION="13.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔨 Starting Metal shader precompilation for MTTransitions${NC}"

# Clean and create directories
rm -rf "$TEMP_DIR"
rm -rf "$OUTPUT_DIR"
mkdir -p "$TEMP_DIR"
mkdir -p "$OUTPUT_DIR"

# Function to compile .metal file to .air
compile_to_air() {
    local metal_file="$1"
    local base_name="$(basename "$metal_file" .metal)"
    local output_air_file="$TEMP_DIR/$base_name.air"

    echo -e "${YELLOW}Compiling $base_name.metal to .air...${NC}"

    # Use iOS simulator SDK for compilation
    xcrun -sdk iphonesimulator metal \
        -c \
        -target air64-apple-ios${IOS_MIN_VERSION}-simulator \
        -std=ios-metal2.4 \
        -mios-version-min=${IOS_MIN_VERSION} \
        -I "$METAL_SOURCE_DIR" \
        -I "./Pods/MetalPetal/Frameworks/MetalPetal/Shaders" \
        "$metal_file" \
        -o "$output_air_file"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Successfully compiled $base_name.metal to .air${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to compile $base_name.metal${NC}"
        return 1
    fi
}

# Function to create .metallib from .air file
create_metallib() {
    local air_file="$1"
    local base_name="$(basename "$air_file" .air)"
    local metallib_file="$OUTPUT_DIR/$base_name.metallib"

    echo -e "${YELLOW}Creating $base_name.metallib...${NC}"

    xcrun -sdk iphonesimulator metallib \
        -o "$metallib_file" \
        "$air_file"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Successfully created $base_name.metallib${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to create $base_name.metallib${NC}"
        return 1
    fi
}

# Check if MetalPetal headers are available
if [ ! -f "./Pods/MetalPetal/Frameworks/MetalPetal/Shaders/MTIShaderLib.h" ]; then
    echo -e "${RED}❌ MetalPetal headers not found. Please run 'pod install' first.${NC}"
    exit 1
fi

# Find and process all .metal files
metal_files_count=0
compiled_count=0
failed_files=()

echo -e "${GREEN}🔍 Finding Metal shader files...${NC}"

while IFS= read -r -d '' metal_file; do
    ((metal_files_count++))
    echo -e "${YELLOW}Processing: $metal_file${NC}"

    if compile_to_air "$metal_file"; then
        base_name="$(basename "$metal_file" .metal)"
        air_file="$TEMP_DIR/$base_name.air"

        if create_metallib "$air_file"; then
            ((compiled_count++))
        else
            failed_files+=("$metal_file")
        fi
    else
        failed_files+=("$metal_file")
    fi

    echo "" # Add spacing between files
done < <(find "$METAL_SOURCE_DIR" -name "*.metal" -print0)

# Clean up temporary files
echo -e "${GREEN}🧹 Cleaning up temporary files...${NC}"
rm -rf "$TEMP_DIR"

# Report results
echo -e "${GREEN}📊 Compilation Summary:${NC}"
echo -e "  Total Metal files found: $metal_files_count"
echo -e "  Successfully compiled: $compiled_count"
echo -e "  Failed: $((metal_files_count - compiled_count))"

if [ ${#failed_files[@]} -gt 0 ]; then
    echo -e "${RED}❌ Failed files:${NC}"
    for file in "${failed_files[@]}"; do
        echo -e "  - $file"
    done
    exit 1
fi

echo -e "${GREEN}🎉 All Metal shaders compiled successfully!${NC}"
echo -e "${GREEN}📁 Precompiled shaders are available in: $OUTPUT_DIR${NC}"

# List generated files
echo -e "${GREEN}📋 Generated metallib files:${NC}"
ls -la "$OUTPUT_DIR"/*.metallib | wc -l | xargs echo "  Total files:"
ls -1 "$OUTPUT_DIR"/*.metallib | head -5 | sed 's/^/  /'
if [ $(ls -1 "$OUTPUT_DIR"/*.metallib | wc -l) -gt 5 ]; then
    echo "  ... and $(($(ls -1 "$OUTPUT_DIR"/*.metallib | wc -l) - 5)) more files"
fi