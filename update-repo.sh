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
# DYNAMIC HTML TWEAK INJECTION FOR LEGACY CYDIA ENGINE WITH .DEB DOWNLOAD LINKS
# ==============================================================================
echo "Updating index.html with live tweak metadata..."

# 1. Clear out any previous dynamically generated tweak lists from index.html
sed -i.bak '/<!-- TWEAKS_START -->/,/<!-- TWEAKS_END -->/{//!d;}' index.html 2>/dev/null || sed -i '' '/<!-- TWEAKS_START -->/,/<!-- TWEAKS_END -->/{//!d;}' index.html

# 2. Parse the metadata database block-by-block and build the replacement HTML list items
HTML_LIST=""
CURRENT_NAME=""
CURRENT_DESC=""
CURRENT_ID=""

while IFS= read -r line || [ -n "$line" ]; do
    # Capture metadata keys using portable string filtering
    if [[ "$line" =~ ^Package:\ (.*) ]]; then
        CURRENT_ID="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^Name:\ (.*) ]]; then
        CURRENT_NAME="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^Description:\ (.*) ]]; then
        CURRENT_DESC="${BASH_REMATCH[1]}"
    # Empty newline delimiter means a tweak definition block has concluded
    elif [[ -z "$line" && -n "$CURRENT_ID" ]]; then
        # Fallbacks if metadata fields are empty
        [ -z "$CURRENT_NAME" ] && CURRENT_NAME="$CURRENT_ID"
        [ -z "$CURRENT_DESC" ] && CURRENT_DESC="No description provided for this jailbreak package."
        
        # Build the exact skeuomorphic list item mapping your required layout syntax
        # The link target is now explicitly hardcoded to append .deb to the bundle identifier
        ITEM="        <li class=\"ios-item\">"
        ITEM="${ITEM}\n            <a href=\"/debs/${CURRENT_ID}.deb\" style=\"text-decoration:none; color:inherit; display:block;\">"
        ITEM="${ITEM}\n                <span class=\"right-align\"><span class=\"chevron\"></span></span>"
        ITEM="${ITEM}\n                <div style=\"font-weight: bold; color: #000000;\">${CURRENT_NAME}</div>"
        ITEM="${ITEM}\n                <div class=\"tweak-desc\">${CURRENT_DESC}</div>"
        ITEM="${ITEM}\n            </a>"
        ITEM="${ITEM}\n        </li>"
        
        HTML_LIST="${HTML_LIST}${ITEM}\n"
        
        # Reset tracker data fields for the next iteration loop pass
        CURRENT_NAME=""
        CURRENT_DESC=""
        CURRENT_ID=""
    fi
done < Packages

# 3. Inject the clean HTML structures directly into index.html
awk -v r="$HTML_LIST" '
  /<!-- TWEAKS_START -->/ { print; print r; next }
  1
' index.html > index.tmp && mv index.tmp index.html

# Wipe build artifacts
rm -f index.html.bak

echo "Success! Your repository index and HTML package list are completely updated."
