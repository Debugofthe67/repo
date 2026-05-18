#!/bin/bash

# Navigate to the folder where the script lives
cd "$(dirname "$0")"

# Ensure the debs directory exists
if [ ! -d "./debs" ]; then
    mkdir ./debs
    echo "Created missing './debs' folder. Place your .deb files there."
    exit 1
fi

# Clean up older index files
echo "Cleaning up old indices..."
rm -f Packages Packages.gz Packages.bz2 Packages.xz Release Release.gpg

echo "Scanning Debian packages..."
dpkg-scanpackages -m ./debs /dev/null > Packages

# Count how many tweaks are currently in the folder
TWEAK_COUNT=$(find ./debs -name "*.deb" | wc -l | tr -d ' ')

# FIX: Check if we are running inside GitHub Codespaces
if [ -n "$GITHUB_REPOSITORY" ]; then
    # Extracts just the repo name from "username/repository-name"
    REPO_NAME=$(basename "$GITHUB_REPOSITORY")
else
    # Fallback to local folder name if running outside of GitHub
    REPO_NAME=$(basename "$(pwd)")
fi

# Create multiple compression formats
echo "Compressing package indices..."
gzip -c9 Packages > Packages.gz
bzip2 -c9 Packages > Packages.bz2
xz -c9 Packages > Packages.xz

# Generate a compliant master Release file using the smart REPO_NAME variable
echo "Generating Release file dynamically..."
cat << EOF > Release
Origin: $REPO_NAME
Label: $REPO_NAME
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm iphoneos-arm64
Components: main
Description: Automated repository for $REPO_NAME containing $TWEAK_COUNT active tweaks. Updated on $(date +%F).
EOF

# Calculate the sizes and checksums dynamically and append to Release
for algo in MD5Sum SHA1 SHA256; do
    echo "${algo}:" >> Release
    for file in Packages Packages.gz Packages.bz2 Packages.xz; do
        if [ -f "$file" ]; then
            size=$(wc -c < "$file" | tr -d ' ')
            
            if [ "$algo" = "MD5Sum" ]; then
                hash=$(md5sum "$file" 2>/dev/null || md5 -q "$file")
            elif [ "$algo" = "SHA1" ]; then
                hash=$(sha1sum "$file" 2>/dev/null || shasum -a 1 "$file" | awk '{print $1}')
            elif [ "$algo" = "SHA256" ]; then
                hash=$(sha256sum "$file" 2>/dev/null || shasum -a 256 "$file" | awk '{print $1}')
            fi
            
            clean_hash=$(echo "$hash" | awk '{print $1}')
            echo " $clean_hash $size $file" >> Release
        fi
    done
done

# Force standard Unix LF line endings to avoid device parsing crashes
sed -i.bak 's/\r$//' Release Packages 2>/dev/null && rm -f Release.bak Packages.bak

echo "Success! Your repository index is updated."
