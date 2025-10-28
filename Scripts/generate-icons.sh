#!/usr/bin/env bash

# LiveClock Icon Generator Script
# Generates all required app icon sizes from SVG template

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Paths
SVG_TEMPLATE="${PROJECT_ROOT}/Resources/icon-template.svg"
SVG_TEMPLATE_MACOS="${PROJECT_ROOT}/Resources/icon-template-macos.svg"
SVG_VISION_BACK="${PROJECT_ROOT}/Resources/icon-visionos-back.svg"
SVG_VISION_MIDDLE="${PROJECT_ROOT}/Resources/icon-visionos-middle.svg"
SVG_VISION_FRONT="${PROJECT_ROOT}/Resources/icon-visionos-front.svg"
ASSETS_DIR="${PROJECT_ROOT}/Sources/Resources/Assets.xcassets"
ICON_SET_DIR="${ASSETS_DIR}/AppIcon.appiconset"
VISION_STACK_DIR="${ASSETS_DIR}/AppIcon.solidimagestack"
TEMP_DIR="${PROJECT_ROOT}/.tmp/icons"

# Check if ImageMagick is installed
check_dependencies() {
    echo -e "${BLUE}Checking dependencies...${NC}"
    
    local missing_deps=false
    
    # Check for ImageMagick
    if ! command -v convert &> /dev/null && ! command -v magick &> /dev/null; then
        echo -e "${RED}✗ ImageMagick is not installed${NC}"
        missing_deps=true
    else
        echo -e "${GREEN}✓ ImageMagick found${NC}"
    fi
    
    # Check for librsvg (optional but recommended)
    if ! command -v rsvg-convert &> /dev/null; then
        echo -e "${YELLOW}⚠ librsvg is not installed (optional but recommended for better SVG rendering)${NC}"
        USE_RSVG=false
    else
        echo -e "${GREEN}✓ librsvg found${NC}"
        USE_RSVG=true
    fi
    
    # Check for bc (required for calculations)
    if ! command -v bc &> /dev/null; then
        echo -e "${RED}✗ bc is not installed${NC}"
        missing_deps=true
    else
        echo -e "${GREEN}✓ bc found${NC}"
    fi
    
    # If any required dependencies are missing, show installation instructions
    if [ "$missing_deps" = true ]; then
        echo ""
        echo -e "${RED}==========================================${NC}"
        echo -e "${RED}   Missing Required Dependencies${NC}"
        echo -e "${RED}==========================================${NC}"
        echo ""
        echo -e "${YELLOW}Please install the required dependencies:${NC}"
        echo ""
        echo -e "${BLUE}For macOS (using Homebrew):${NC}"
        echo -e "  ${GREEN}brew install imagemagick bc${NC}"
        echo ""
        echo -e "${BLUE}For better SVG rendering (optional):${NC}"
        echo -e "  ${GREEN}brew install librsvg${NC}"
        echo ""
        echo -e "${BLUE}To install all at once:${NC}"
        echo -e "  ${GREEN}brew install imagemagick librsvg bc${NC}"
        echo ""
        echo -e "${YELLOW}After installation, please run this script again.${NC}"
        echo ""
        exit 1
    fi
    
    echo -e "${GREEN}All required dependencies are installed${NC}"
}

# Create directories
setup_directories() {
    echo -e "${BLUE}Setting up directories...${NC}"
    
    # Create temp directory
    mkdir -p "${TEMP_DIR}"
    
    # Create Assets.xcassets if it doesn't exist
    mkdir -p "${ASSETS_DIR}"
    
    # Create AppIcon.appiconset
    mkdir -p "${ICON_SET_DIR}"
    
    # Create AppIcon.solidimagestack for visionOS
    mkdir -p "${VISION_STACK_DIR}"
    
    echo -e "${GREEN}Directories created${NC}"
}

# Icon sizes configuration
# Format: size@scale:idiom:description
declare -a ICON_SIZES=(
    # iPhone Notification
    "20@2x:iphone:iPhone Notification @2x"
    "20@3x:iphone:iPhone Notification @3x"
    
    # iPhone Settings
    "29@2x:iphone:iPhone Settings @2x"
    "29@3x:iphone:iPhone Settings @3x"
    
    # iPhone Spotlight
    "40@2x:iphone:iPhone Spotlight @2x"
    "40@3x:iphone:iPhone Spotlight @3x"
    
    # iPhone App
    "60@2x:iphone:iPhone App @2x"
    "60@3x:iphone:iPhone App @3x"
    
    # iPad Notification
    "20@1x:ipad:iPad Notification @1x"
    "20@2x:ipad:iPad Notification @2x"
    
    # iPad Settings
    "29@1x:ipad:iPad Settings @1x"
    "29@2x:ipad:iPad Settings @2x"
    
    # iPad Spotlight
    "40@1x:ipad:iPad Spotlight @1x"
    "40@2x:ipad:iPad Spotlight @2x"
    
    # iPad App
    "76@1x:ipad:iPad App @1x"
    "76@2x:ipad:iPad App @2x"
    
    # iPad Pro App
    "83.5@2x:ipad:iPad Pro App @2x"
    
    # iOS Marketing
    "1024@1x:ios-marketing:App Store @1x"
    
    # macOS icons
    "16@1x:mac:macOS 16pt @1x"
    "16@2x:mac:macOS 16pt @2x"
    "32@1x:mac:macOS 32pt @1x"
    "32@2x:mac:macOS 32pt @2x"
    "128@1x:mac:macOS 128pt @1x"
    "128@2x:mac:macOS 128pt @2x"
    "256@1x:mac:macOS 256pt @1x"
    "256@2x:mac:macOS 256pt @2x"
    "512@1x:mac:macOS 512pt @1x"
    "512@2x:mac:macOS 512pt @2x"
)

# Generate PNG from SVG using either rsvg-convert or ImageMagick
generate_png() {
    local size=$1
    local output=$2
    local svg_file=$3
    
    # Use default template if not specified
    if [ -z "$svg_file" ]; then
        svg_file="${SVG_TEMPLATE}"
    fi
    
    if [ "$USE_RSVG" = true ]; then
        rsvg-convert -w "${size}" -h "${size}" "${svg_file}" -o "${output}"
    else
        convert -background none -resize "${size}x${size}" "${svg_file}" "${output}"
    fi
}

# Generate all icon sizes
generate_icons() {
    echo -e "${BLUE}Generating icons...${NC}"
    
    for config in "${ICON_SIZES[@]}"; do
        IFS=':' read -r size_scale idiom description <<< "$config"
        IFS='@' read -r base_size scale <<< "$size_scale"
        
        # Calculate actual pixel size
        if [[ "$scale" == "1x" ]]; then
            pixel_size=$(echo "$base_size" | bc)
        elif [[ "$scale" == "2x" ]]; then
            pixel_size=$(echo "$base_size * 2" | bc)
        elif [[ "$scale" == "3x" ]]; then
            pixel_size=$(echo "$base_size * 3" | bc)
        fi
        
        # Generate filename
        if [[ "$idiom" == "ios-marketing" ]]; then
            filename="icon-1024.png"
        elif [[ "$idiom" == "mac" ]]; then
            filename="icon-mac-${base_size}@${scale}.png"
        else
            filename="icon-${base_size}@${scale}.png"
        fi
        
        output_path="${ICON_SET_DIR}/${filename}"
        
        echo -e "  Generating ${description} (${pixel_size}x${pixel_size}px) -> ${filename}"
        
        # Use rounded corner SVG for macOS icons
        if [[ "$idiom" == "mac" ]]; then
            generate_png "${pixel_size}" "${output_path}" "${SVG_TEMPLATE_MACOS}"
        else
            generate_png "${pixel_size}" "${output_path}" "${SVG_TEMPLATE}"
        fi
    done
    
    echo -e "${GREEN}Icons generated successfully${NC}"
}

# Generate Contents.json for the icon set
generate_contents_json() {
    echo -e "${BLUE}Generating Contents.json...${NC}"
    
    cat > "${ICON_SET_DIR}/Contents.json" << 'EOF'
{
  "images" : [
    {
      "filename" : "icon-20@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "20x20"
    },
    {
      "filename" : "icon-20@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "20x20"
    },
    {
      "filename" : "icon-29@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "icon-29@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "29x29"
    },
    {
      "filename" : "icon-40@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "40x40"
    },
    {
      "filename" : "icon-40@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "40x40"
    },
    {
      "filename" : "icon-60@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "60x60"
    },
    {
      "filename" : "icon-60@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "60x60"
    },
    {
      "filename" : "icon-20@1x.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "20x20"
    },
    {
      "filename" : "icon-20@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "20x20"
    },
    {
      "filename" : "icon-29@1x.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "29x29"
    },
    {
      "filename" : "icon-29@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "icon-40@1x.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "40x40"
    },
    {
      "filename" : "icon-40@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "40x40"
    },
    {
      "filename" : "icon-76@1x.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "76x76"
    },
    {
      "filename" : "icon-76@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "76x76"
    },
    {
      "filename" : "icon-83.5@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "83.5x83.5"
    },
    {
      "filename" : "icon-1024.png",
      "idiom" : "ios-marketing",
      "scale" : "1x",
      "size" : "1024x1024"
    },
    {
      "filename" : "icon-mac-16@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon-mac-16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon-mac-32@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon-mac-32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon-mac-128@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon-mac-128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon-mac-256@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon-mac-256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon-mac-512@1x.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon-mac-512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
    
    echo -e "${GREEN}Contents.json generated${NC}"
}

# Generate visionOS solid image stack
generate_visionos_stack() {
    echo -e "${BLUE}Generating visionOS solid image stack...${NC}"
    
    # Check if visionOS SVG templates exist
    if [ ! -f "${SVG_VISION_BACK}" ] || [ ! -f "${SVG_VISION_MIDDLE}" ] || [ ! -f "${SVG_VISION_FRONT}" ]; then
        echo -e "${YELLOW}Warning: visionOS layer SVGs not found. Skipping visionOS stack generation.${NC}"
        echo -e "${YELLOW}Expected files:${NC}"
        echo -e "  - ${SVG_VISION_BACK}"
        echo -e "  - ${SVG_VISION_MIDDLE}"
        echo -e "  - ${SVG_VISION_FRONT}"
        return
    fi
    
    # visionOS requires three layers for the solid image stack:
    # - Back layer (background gradient and clock face)
    # - Middle layer (hour markers and clock hands)
    # - Front layer (stopwatch button, digital display, highlight)
    
    # Create layer directories with Content.imageset subdirectories
    mkdir -p "${VISION_STACK_DIR}/Back.imagestacklayer/Content.imageset"
    mkdir -p "${VISION_STACK_DIR}/Middle.imagestacklayer/Content.imageset"
    mkdir -p "${VISION_STACK_DIR}/Front.imagestacklayer/Content.imageset"
    
    # Back layer - 1024x1024 for visionOS
    echo -e "  Generating Back layer (background and clock face)..."
    if [ "$USE_RSVG" = true ]; then
        rsvg-convert -w 1024 -h 1024 "${SVG_VISION_BACK}" -o "${VISION_STACK_DIR}/Back.imagestacklayer/Content.imageset/Content.png"
    else
        convert -background none -resize 1024x1024 "${SVG_VISION_BACK}" "${VISION_STACK_DIR}/Back.imagestacklayer/Content.imageset/Content.png"
    fi
    
    # Middle layer - 1024x1024 for visionOS
    echo -e "  Generating Middle layer (hour markers and hands)..."
    if [ "$USE_RSVG" = true ]; then
        rsvg-convert -w 1024 -h 1024 "${SVG_VISION_MIDDLE}" -o "${VISION_STACK_DIR}/Middle.imagestacklayer/Content.imageset/Content.png"
    else
        convert -background none -resize 1024x1024 "${SVG_VISION_MIDDLE}" "${VISION_STACK_DIR}/Middle.imagestacklayer/Content.imageset/Content.png"
    fi
    
    # Front layer - 1024x1024 for visionOS
    echo -e "  Generating Front layer (button, display, highlight)..."
    if [ "$USE_RSVG" = true ]; then
        rsvg-convert -w 1024 -h 1024 "${SVG_VISION_FRONT}" -o "${VISION_STACK_DIR}/Front.imagestacklayer/Content.imageset/Content.png"
    else
        convert -background none -resize 1024x1024 "${SVG_VISION_FRONT}" "${VISION_STACK_DIR}/Front.imagestacklayer/Content.imageset/Content.png"
    fi
    
    # Create Contents.json for each layer
    echo -e "  Creating layer Contents.json files..."
    
    # Back layer Contents.json files
    cat > "${VISION_STACK_DIR}/Back.imagestacklayer/Contents.json" << 'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
    
    cat > "${VISION_STACK_DIR}/Back.imagestacklayer/Content.imageset/Contents.json" << 'EOF'
{
  "images" : [
    {
      "filename" : "Content.png",
      "idiom" : "vision",
      "scale" : "2x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
    
    # Middle layer Contents.json files
    cat > "${VISION_STACK_DIR}/Middle.imagestacklayer/Contents.json" << 'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
    
    cat > "${VISION_STACK_DIR}/Middle.imagestacklayer/Content.imageset/Contents.json" << 'EOF'
{
  "images" : [
    {
      "filename" : "Content.png",
      "idiom" : "vision",
      "scale" : "2x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
    
    # Front layer Contents.json files
    cat > "${VISION_STACK_DIR}/Front.imagestacklayer/Contents.json" << 'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
    
    cat > "${VISION_STACK_DIR}/Front.imagestacklayer/Content.imageset/Contents.json" << 'EOF'
{
  "images" : [
    {
      "filename" : "Content.png",
      "idiom" : "vision",
      "scale" : "2x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
    
    # Create main Contents.json for the solid image stack
    cat > "${VISION_STACK_DIR}/Contents.json" << 'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "layers" : [
    {
      "filename" : "Front.imagestacklayer"
    },
    {
      "filename" : "Middle.imagestacklayer"
    },
    {
      "filename" : "Back.imagestacklayer"
    }
  ]
}
EOF
    
    echo -e "${GREEN}visionOS solid image stack generated${NC}"
}

# Clean up temporary files
cleanup() {
    echo -e "${BLUE}Cleaning up...${NC}"
    if [ -d "${TEMP_DIR}" ]; then
        rm -rf "${TEMP_DIR}"
    fi
    echo -e "${GREEN}Cleanup complete${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}   LiveClock Icon Generator${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
    
    # Check if SVG templates exist
    if [ ! -f "${SVG_TEMPLATE}" ]; then
        echo -e "${RED}Error: SVG template not found at ${SVG_TEMPLATE}${NC}"
        exit 1
    fi
    
    if [ ! -f "${SVG_TEMPLATE_MACOS}" ]; then
        echo -e "${RED}Error: macOS SVG template not found at ${SVG_TEMPLATE_MACOS}${NC}"
        exit 1
    fi
    
    check_dependencies
    setup_directories
    generate_icons
    generate_contents_json
    generate_visionos_stack
    cleanup
    
    echo ""
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}   Icon generation completed!${NC}"
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}iOS/macOS icons saved to: ${ICON_SET_DIR}${NC}"
    echo -e "${GREEN}visionOS stack saved to: ${VISION_STACK_DIR}${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "  1. Review the generated icons in Xcode"
    echo -e "  2. Update Project.swift to reference the AppIcon assets"
    echo -e "  3. For visionOS, use AppIcon.solidimagestack"
    echo -e "  4. Build and test the app with the new icons"
}

# Handle script interruption
trap cleanup EXIT

# Run main function
main "$@"