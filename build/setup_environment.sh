#!/bin/bash
# Environment setup script for Yoga Book YB1-91F Android build

echo "Setting up Android build environment for Yoga Book YB1-91F..."

# Check if we're on Ubuntu/Linux (required for Android build)
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Linux environment detected"
else
    echo "Warning: Android builds typically require Linux environment"
    echo "Consider using WSL2 or a Linux VM for actual builds"
fi

# Create local manifest for Yoga Book specific repositories
mkdir -p .repo/local_manifests

cat > .repo/local_manifests/yogabook.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <!-- Yoga Book specific kernel -->
    <remote name="yogabook" 
            fetch="https://github.com/Yoga-Book" 
            review="https://github.com/Yoga-Book" />
    
    <!-- Kernel repository -->
    <project path="kernel/lenovo/yogabook" 
             name="Yoga-Book-Linux-Kernel" 
             remote="yogabook" 
             revision="submission/yogabook-x91l-v2" />
    
    <!-- Sound firmware -->
    <project path="vendor/lenovo/yogabook/sound-firmware" 
             name="Yoga-Book-Sound-Open-Firmware" 
             remote="yogabook" 
             revision="submission/cht-rt5677-topology2-ipc3-v1" />
    
    <!-- Camera drivers -->
    <project path="vendor/lenovo/yogabook/camera" 
             name="Yoga-Book-Camera" 
             remote="yogabook" 
             revision="main" />
    
    <!-- Halo Keyboard -->
    <project path="vendor/lenovo/yogabook/halo-keyboard" 
             name="Halo-Keyboard" 
             remote="yogabook" 
             revision="main" />
    
    <!-- Sensors -->
    <project path="vendor/lenovo/yogabook/sensors" 
             name="Yoga-Book-Sensors" 
             remote="yogabook" 
             revision="main" />
    
    <!-- ALSA UCM Config -->
    <project path="hardware/lenovo/yogabook/alsa-ucm" 
             name="Yoga-Book-ALSA-UCM-Config" 
             remote="yogabook" 
             revision="main" />
    
    <!-- Ubuntu Autoinstall (reference) -->
    <project path="vendor/lenovo/yogabook/ubuntu-autoinstall" 
             name="Ubuntu-Autoinstall" 
             remote="yogabook" 
             revision="main" />
</manifest>
EOF

echo "Local manifest created for Yoga Book repositories"
echo "To sync: repo sync"