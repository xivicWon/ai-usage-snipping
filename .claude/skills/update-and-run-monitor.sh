#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

APP_NAME="ClaudeMonitor"
APPS_DIR="/Applications"
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  ClaudeMonitor Update & Launch${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Check prerequisites
echo -e "\n${YELLOW}[1/4]${NC} Checking prerequisites..."
if ! command -v xcodebuild &> /dev/null; then
  echo -e "${RED}✗ Xcode is not installed${NC}"
  echo "Install Xcode Command Line Tools: xcode-select --install"
  exit 1
fi

if ! command -v xcodegen &> /dev/null; then
  echo -e "${RED}✗ XcodeGen is not installed${NC}"
  echo "Install with: brew install xcodegen"
  exit 1
fi
echo -e "${GREEN}✓ Prerequisites met${NC}"

# Step 1: Generate Xcode project if needed
echo -e "\n${YELLOW}[2/4]${NC} Preparing Xcode project..."
cd "$PROJECT_DIR"
if [ ! -f "ClaudeMonitor.xcodeproj/project.pbxproj" ]; then
  echo "Generating project from project.yml..."
  xcodegen generate
fi
echo -e "${GREEN}✓ Xcode project ready${NC}"

# Step 2: Build DMG
echo -e "\n${YELLOW}[3/4]${NC} Building ClaudeMonitor..."
bash "$PROJECT_DIR/scripts/build-dmg.sh"
echo -e "${GREEN}✓ Build complete${NC}"

# Step 3: Find and install DMG
echo -e "\n${YELLOW}[4/4]${NC} Installing to Applications..."
DMG_FILE=$(find "$PROJECT_DIR" -maxdepth 1 -name "ClaudeMonitor-*.dmg" -type f | head -1)

if [ -z "$DMG_FILE" ]; then
  echo -e "${RED}✗ DMG file not found after build${NC}"
  exit 1
fi

echo "Mounting $DMG_FILE..."
MOUNT_POINT=$(mktemp -d)
hdiutil attach "$DMG_FILE" -mountpoint "$MOUNT_POINT" -quiet

if [ -d "$MOUNT_POINT/$APP_NAME.app" ]; then
  rm -rf "$APPS_DIR/$APP_NAME.app"
  cp -r "$MOUNT_POINT/$APP_NAME.app" "$APPS_DIR/"
  echo -e "${GREEN}✓ Installed to $APPS_DIR/$APP_NAME.app${NC}"
else
  echo -e "${RED}✗ Could not find $APP_NAME.app in mounted DMG${NC}"
  hdiutil detach "$MOUNT_POINT" -quiet
  exit 1
fi

# Cleanup and launch
hdiutil detach "$MOUNT_POINT" -quiet
rm -rf "$MOUNT_POINT"

echo -e "\nLaunching ClaudeMonitor..."
open "$APPS_DIR/$APP_NAME.app"
echo -e "${GREEN}✓ ClaudeMonitor is launching...${NC}"

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Successfully built and launched ClaudeMonitor${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
