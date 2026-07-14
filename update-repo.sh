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


# ==============================================================================
# DYNAMIC HTML TWEAK INJECTION WITH DUPES/VERSION FILTERING
# ==============================================================================
echo "Updating index.html with live tweak metadata (filtering duplicates)..."

# 1. Clear out any previous dynamically generated tweak lists from index.html
sed -i.bak '/<!-- TWEAKS_START -->/,/<!-- TWEAKS_END -->/{//!d;}' index.html 2>/dev/null || sed -i '' '/<!-- TWEAKS_START -->/,/<!-- TWEAKS_END -->/{//!d;}' index.html

# 2. Parse Packages file using an internal associative memory map via Awk
# This logic groups duplicates by Package ID, compares versions, and outputs the highest version
HTML_LIST=$(awk '
BEGIN {
    # Define field delimiters
    RS = ""
    FS = "\n"
}
{
    # Loop through lines of a single tweak block
    id = ""
    name = ""
    desc = ""
    ver = ""
    
    for (i = 1; i <= NF; i++) {
        if ($i ~ /^Package:/) { sub(/^Package: /, "", $i); id = $i }
        if ($i ~ /^Name:/) { sub(/^Name: /, "", $i); name = $i }
        if ($i ~ /^Description:/) { sub(/^Description: /, "", $i); desc = $i }
        if ($i ~ /^Version:/) { sub(/^Version: /, "", $i); ver = $i }
    }
    
    if (id != "") {
        # Fallbacks for empty metadata fields
        if (name == "") name = id
        if (desc == "") desc = "No description provided for this jailbreak package."
        
        # If this package is new, or if this version is higher than our saved version, track it
        # Note: Simple string/alphanumeric verification loop for lightweight environments
        if (!(id in saved_version) || ver > saved_version[id]) {
            saved_version[id] = ver
            saved_name[id] = name
            saved_desc[id] = desc
        }
    }
}
END {
    # Generate the clean skeuomorphic HTML components for the single highest versions
    for (id in saved_version) {
        print "        <li class=\"ios-item\">"
        print "            <a href=\"/debs/" id ".deb\" style=\"text-decoration:none; color:inherit; display:block;\">"
        print "                <span class=\"right-align\"><span class=\"chevron\"></span></span>"
        print "                <div style=\"font-weight: bold; color: #000000;\">" saved_name[id] " <span style=\"font-size:11px; color:#8e8e93; font-weight:normal;\">v" saved_version[id] "</span></div>"
        print "                <div class=\"tweak-desc\">" saved_desc[id] "</div>"
        print "            </a>"
        print "        </li>"
    }
}' Packages)

# 3. Inject the filtered clean HTML structures directly into index.html
awk -v r="$HTML_LIST" '
  /<!-- TWEAKS_START -->/ { print; print r; next }
  1
' index.html > index.tmp && mv index.tmp index.html

# Wipe build artifacts
rm -f index.html.bak

echo "Success! Your repository index and HTML package list are completely updated."
