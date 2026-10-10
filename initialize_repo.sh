#!/bin/bash
# Script to initialize the Yoga Book Android repository

echo "Initializing Yoga Book YB1-91F Android repository..."

# Check if repo tool is available
if ! command -v repo &> /dev/null; then
    echo "Error: repo tool not found. Please install it first:"
    echo "  mkdir -p ~/bin"
    echo "  curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo"
    echo "  chmod a+x ~/bin/repo"
    echo "  export PATH=~/bin:\$PATH"
    exit 1
fi

# Initialize repo with AOSP manifest
echo "Initializing repo with AOSP android-13.0.0_r41 manifest..."
repo init -u https://android.googlesource.com/platform/manifest -b android-13.0.0_r41

if [ $? -ne 0 ]; then
    echo "Error: Failed to initialize repo"
    exit 1
fi

# Copy Yoga Book local manifest
echo "Copying Yoga Book local manifest..."
cp build/yogabook.xml .repo/local_manifests/

if [ $? -ne 0 ]; then
    echo "Error: Failed to copy local manifest"
    exit 1
fi

# Sync all repositories
echo "Syncing all repositories (this may take a while)..."
repo sync -j$(nproc) --no-clone-bundle --no-tags

if [ $? -ne 0 ]; then
    echo "Error: Repository sync failed"
    echo "You may need to run: repo sync -j$(nproc) to retry"
    exit 1
fi

echo ""
echo "Repository initialization complete!"
echo ""
echo "Next steps:"
echo "1. Apply kernel patches: ./build/apply_kernel_patches.sh"
echo "2. Setup build environment: source build/envsetup.sh"
echo "3. Select target: yogabook_lunch (or lunch aosp_yogabook-userdebug)"
echo "4. Build: m -j$(nproc)"
echo ""
echo "For detailed instructions, see BUILD_GUIDE.md"