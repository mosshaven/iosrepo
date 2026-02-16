#!/bin/bash

# IPA to DEB Converter for iOS
# Usage: ./ipa2deb.sh <input.ipa> [output.deb]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if input file is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <input.ipa> [output.deb]"
    echo "Example: $0 app.ipa app.deb"
    exit 1
fi

INPUT_IPA="$1"
OUTPUT_DEB="${2:-$(basename "$INPUT_IPA" .ipa).deb}"

# Check if input file exists
if [ ! -f "$INPUT_IPA" ]; then
    print_error "Input file '$INPUT_IPA' not found!"
    exit 1
fi

# Check if input is actually an IPA file
if [[ ! "$INPUT_IPA" =~ \.ipa$ ]]; then
    print_error "Input file must have .ipa extension!"
    exit 1
fi

print_status "Starting conversion: $INPUT_IPA -> $OUTPUT_DEB"

# Create temporary working directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

print_status "Created temporary directory: $TEMP_DIR"

# Extract IPA file
print_status "Extracting IPA file..."
unzip -q "$INPUT_IPA" -d "$TEMP_DIR"

# Find Payload directory
PAYLOAD_DIR="$TEMP_DIR/Payload"
if [ ! -d "$PAYLOAD_DIR" ]; then
    print_error "Payload directory not found in IPA file!"
    exit 1
fi

# Get app bundle
APP_BUNDLE=$(find "$PAYLOAD_DIR" -name "*.app" -type d | head -n 1)
if [ -z "$APP_BUNDLE" ]; then
    print_error "No .app bundle found in Payload!"
    exit 1
fi

APP_NAME=$(basename "$APP_BUNDLE")
print_status "Found app bundle: $APP_NAME"

# Create DEB structure
DEB_DIR="$TEMP_DIR/deb"
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/var/mobile/Documents"

# Copy app to destination
print_status "Copying app bundle..."
cp -r "$APP_BUNDLE" "$DEB_DIR/var/mobile/Documents/"

# Create control file
print_status "Creating control file..."
cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: $(echo "$APP_NAME" | sed 's/\.app$//' | tr '[:upper:]' '[:lower:]')
Name: $APP_NAME
Version: 1.0
Architecture: iphoneos-arm
Description: Converted from $INPUT_IPA
Maintainer: IPA2DEB Converter
Section: Utilities
Depends: firmware (>= 1.0)
EOF

# Create postinst script for app installation
cat > "$DEB_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/bash

# Find the app in Documents and move to Applications
APP_DIR=$(find /var/mobile/Documents -name "*.app" -type d | head -n 1)

if [ -n "$APP_DIR" ]; then
    APP_NAME=$(basename "$APP_DIR")
    
    # Create Applications directory if it doesn't exist
    mkdir -p /var/mobile/Containers/Bundle/Application
    
    # Find a suitable location or create one
    TARGET_DIR="/var/mobile/Containers/Bundle/Application/$APP_NAME"
    
    # Move app
    mv "$APP_DIR" "$TARGET_DIR"
    
    # Set permissions
    chown -R mobile:mobile "$TARGET_DIR"
    chmod -R 755 "$TARGET_DIR"
    
    # Respring
    killall SpringBoard 2>/dev/null || true
    
    echo "App installed successfully!"
else
    echo "No app bundle found!"
fi
EOF

chmod +x "$DEB_DIR/DEBIAN/postinst"

# Create prerm script for app removal
cat > "$DEB_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/bash

# Find and remove the app
APP_DIR=$(find /var/mobile/Containers/Bundle/Application -name "*.app" -type d 2>/dev/null | head -n 1)

if [ -n "$APP_DIR" ]; then
    rm -rf "$APP_DIR"
    echo "App removed successfully!"
fi
EOF

chmod +x "$DEB_DIR/DEBIAN/prerm"

# Build DEB package
print_status "Building DEB package..."
dpkg-deb -b "$DEB_DIR" "$OUTPUT_DEB"

# Check if DEB was created successfully
if [ -f "$OUTPUT_DEB" ]; then
    SIZE=$(du -h "$OUTPUT_DEB" | cut -f1)
    print_status "Conversion completed successfully!"
    print_status "Output: $OUTPUT_DEB (Size: $SIZE)"
else
    print_error "Failed to create DEB package!"
    exit 1
fi

print_status "Done! You can now install the DEB package on your iOS device."
