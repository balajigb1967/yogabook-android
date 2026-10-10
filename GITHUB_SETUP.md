# GitHub Setup for Yoga Book YB1-91F Android Project

This guide explains how to set up and use your GitHub repository (https://github.com/balajigb1967/yogabook-android) for the Yoga Book YB1-91F Android build.

## Repository Status

Your local project has been initialized as a Git repository and is ready to be connected to your GitHub account. The initial commit contains all the necessary build configuration files.

## Manual GitHub Connection

Since automatic pushing encountered credential issues, please follow these steps to connect your local repository to GitHub:

### 1. Create Personal Access Token (if needed)

If you have 2FA enabled on GitHub, you'll need a Personal Access Token:
1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Click "Generate new token"
3. Select scopes: `repo` (full control of private repositories)
4. Copy the generated token

### 2. Connect Local Repository to GitHub

```bash
# Navigate to your project directory
cd C:\Ubuntu-waydroid\yogabook-android

# Add GitHub remote (replace with your actual credentials)
git remote add origin https://github.com/balajigb1967/yogabook-android.git

# Set main branch
git branch -M main

# Push to GitHub (you'll be prompted for credentials)
git push -u origin main
```

### 3. Alternative: Use SSH (Recommended for frequent pushes)

1. Generate SSH key if you don't have one:
   ```bash
   ssh-keygen -t ed25519 -C "balajigb1967@example.com"
   ```

2. Add the public key (`~/.ssh/id_ed25519.pub`) to your GitHub account:
   - GitHub → Settings → SSH and GPG keys → New SSH key

3. Connect using SSH:
   ```bash
   git remote set-url origin git@github.com:balajigb1967/yogabook-android.git
   git push -u origin main
   ```

## Using GitHub in the Build Process

Your GitHub repository will serve as:

### 1. **Backup and Version Control**
- Track all changes to your Android build configuration
- Rollback to previous working configurations
- Collaborate with others if needed

### 2. **Host Custom Patches and Configurations**
You can create branches for:
- `kernel/6.18-backports` - For backported drivers to 6.18 kernel
- `kernel/7.2-experimental` - For experimenting with newer kernels
- `vendor/yogabook-proprietary` - For vendor-specific blobs (private)
- `device/lenovo/yogabook/patches` - For device-specific patches

### 3. **Automated Builds (Future)**
You can set up GitHub Actions for automated builds:
```yaml
# .github/workflows/android-build.yml
name: Android Build

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - name: Set up JDK 11
      uses: actions/setup-java@v3
      with:
        java-version: '11'
        distribution: 'temurin'
    - name: Setup Android build environment
      run: |
        sudo apt-get update
        sudo apt-get install -y git-core gnupg flex bison gperf build-essential \
          zip curl zlib1g-dev libc6-dev lib32ncurses6 lib32z1 lib32stdc++6 \
          libssl-dev libffi-dev
    - name: Install repo
      run: |
        mkdir -p ~/bin
        curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
        chmod a+x ~/bin/repo
        export PATH=~/bin:$PATH
    - name: Initialize and sync
      run: |
        ./initialize_repo.sh
    - name: Build Android
      run: |
        source build/envsetup.sh
        yogabook_lunch
        m -j$(nproc)
```

## Repository Structure for GitHub

Your GitHub repo should contain:
```
/ (root)
├── BUILD_GUIDE.md
├── GITHUB_SETUP.md          ← This file
├── initialize_repo.sh
├── README.md
├── build/
│   ├── apply_kernel_patches.sh
│   ├── config.yaml
│   ├── create_flashable.sh
│   ├── envsetup.sh
│   ├── make_kernel.sh
│   ├── setup_environment.sh
│   └── yogabook.xml
├── device/
│   └── lenovo/
│       └── yogabook/
├── hardware/
│   └── lenovo/
│       └── yogabook/
├── vendor/
│   └── lenovo/
│       └── yogabook└── kernel/
└── external/
    └── yogabook-mutter/
```

## Recommended Workflow

1. **Development Branch Strategy**
   - `main` - Stable, tested builds
   - `dev` - Active development
   - `feature/<feature-name>` - Specific feature work (e.g., `feature/halokeyboard`)
   - `bugfix/<issue>` - Bug fixes
   - `release/<version>` - Release candidates

2. **Regular Updates from Yoga Book Repos**
   Periodically update from the official Yoga Book repositories:
   ```bash
   # Update kernel
   cd kernel/lenovo/yogabook
   git fetch origin
   git checkout submission/yogabook-x91l-v2
   git pull

   # Update other repos similarly...
   ```

3. **Track Your Customizations**
   Keep your custom patches and configurations in your GitHub repo:
   - Custom kernel configs
   - Modified HAL implementations
   - Device-specific properties
   - Build script modifications

## Troubleshooting GitHub Connection

### Common Issues and Solutions

**Authentication Failed:**
- Use Personal Access Token instead of password
- Ensure SSH key is properly added to GitHub
- Check system clock time sync

**Repository Not Found:**
- Verify repository name spelling
- Ensure repository is not private without proper access
- Check URL: `https://github.com/balajigb1967/yogabook-android.git`

**Push Rejected:**
- Pull latest changes first: `git pull origin main`
- Resolve any merge conflicts
- Force push only if necessary: `git push --force-with-lease`

## Next Steps

1. Connect your local repo to GitHub using the instructions above
2. Make your initial push to establish the remote connection
3. Begin development by making changes and committing regularly
4. Consider setting up branch protection rules on GitHub for main branch
5. Explore GitHub Projects or Issues for tracking development progress

## Backup Your Work

Remember to:
- Commit frequently: `git add . && git commit -m "Descriptive message"`
- Push regularly: `git push origin main`
- Create branches for experimental work
- Tag releases: `git tag -a v1.0 -m "Initial Android build" && git push origin v1.0`

Your Yoga Book YB1-91F Android project is now ready for GitHub-based development!