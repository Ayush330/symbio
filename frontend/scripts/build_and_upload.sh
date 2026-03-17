#!/bin/bash

# symbio_build_and_upload.sh
# Automates Flutter Android Release Build with Auto-Versioning and GDrive Upload

# Usage Guide:
# 1. Create a `.env.release` file in the project root based on `.env.release.template`.
# 2. Ensure `GDRIVE_FOLDER_ID` is set in `.env.release` for Google Drive upload.
# 3. Make sure `python3` is installed if you want to use Google Drive upload.
# 4. Run this script from the project root: `./scripts/build_and_upload.sh`

# Exit on error
set -e

# 1. Load configuration
if [ -f .env.release ]; then
    # Filter out comments and empty lines before exporting
    export $(grep -v '^#' .env.release | grep -v '^[[:space:]]*$' | xargs)
else
    echo "⚠️ .env.release not found. Please create it based on the template."
    exit 1
fi

# 2. Extract and Increment Version
# Current version format in pubspec.yaml is usually 'version: 1.0.0+1'
CURRENT_VERSION_LINE=$(grep "version: " pubspec.yaml)
VERSION_PART=$(echo $CURRENT_VERSION_LINE | cut -d' ' -f2 | cut -d'+' -f1)
BUILD_PART=$(echo $CURRENT_VERSION_LINE | cut -d'+' -f2)

NEW_BUILD=$((BUILD_PART + 1))
NEW_VERSION_LINE="version: $VERSION_PART+$NEW_BUILD"

echo "🚀 Bumping version: $VERSION_PART+$BUILD_PART -> $VERSION_PART+$NEW_BUILD"

# Use sed to update pubspec.yaml
# (MacOS sed requires an empty string for the -i flag)
sed -i '' "s/version: .*/$NEW_VERSION_LINE/" pubspec.yaml

# 3. Clean and Build
echo "🧹 Cleaning previous builds..."
flutter clean

echo "🏗️ Building Release APK..."
flutter build apk --release

# 4. Rename and Move
APK_NAME="kizuna_$VERSION_PART+$NEW_BUILD.apk"
SOURCE_APK="build/app/outputs/flutter-apk/app-release.apk"
TARGET_PATH="scripts/$APK_NAME"

mv "$SOURCE_APK" "$TARGET_PATH"

echo "✅ Build Complete: $TARGET_PATH"

# 5. Upload to Google Drive (if GDRIVE_FOLDER_ID is set)
if [ ! -z "$GDRIVE_FOLDER_ID" ]; then
    echo "☁️ Uploading to Google Drive..."
    # Check if python3 is installed
    if command -v python3 &> /dev/null; then
        echo "🐍 Setting up Python Virtual Environment..."
        
        # Create venv if it doesn't exist
        if [ ! -d "scripts/venv" ]; then
            python3 -m venv scripts/venv
        fi
        
        # Activate and install dependencies
        source scripts/venv/bin/activate
        echo "📦 Installing/Checking Python dependencies..."
        pip install -q -r scripts/requirements.txt
        
        # Run the upload
        python3 scripts/upload_to_drive.py "$TARGET_PATH" "$GDRIVE_FOLDER_ID"
        
        # Deactivate
        deactivate
        echo "🎉 Upload process finished!"
    else
        echo "❌ 'python3' command not found. Skipping upload."
        echo "💡 Place your APK manually or install python requirements."
    fi
else
    echo "⏭️ GDRIVE_FOLDER_ID not set in .env.release. Skipping upload."
fi
