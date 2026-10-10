#!/bin/bash
# Environment setup for Yoga Book Android build

echo "Setting up Yoga Book Android build environment..."

# Add build helper scripts to PATH
export PATH="$PATH:$(pwd)/build"

# Set up common build variables
export YOGABOOK_DEVICE=yogabook
export YOGABOOK_BRAND=Lenovo
export YOGABOOK_MODEL="Yoga Book YB1-91F"

# Function to lunch Yoga Book target
yogabook_lunch() {
    echo "Available Yoga Book lunch targets:"
    echo "  aosp_yogabook-userdebug"
    echo "  aosp_yogabook-eng"
    echo ""
    read -p "Select target (or press Enter for userdebug): " target
    if [ -z "$target" ]; then
        target="aosp_yogabook-userdebug"
    fi
    lunch $target
}

# Export the lunch function
export -f yogabook_lunch

echo "Environment setup complete!"
echo "Use 'yogabook_lunch' to select a target, then 'm' to build"