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

# ==============================================================================
# CUSTOM REPOSITORY METADATA CONFIGURATION (MANUAL HARDCODE)
# ==============================================================================
REPO_NAME="TP67"
REPO_LABEL="TP67"

# Create multiple compression formats
echo "Compressing package indices..."
gzip -c9 Packages > Packages.gz
bzip2 -c9 Packages > Packages.bz2
xz -c9 Packages > Packages.xz

# Generate a compliant master Release file
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
# ABSOLUTE REPOSITORY PATH HTML GENERATION (FIXES GITHUB PAGES 404)
# ==============================================================================
echo "Updating index.html with absolute repository subfolder mapping..."

# 1. Clear out any previous dynamically generated tweak lists from index.html
sed -i.bak '/<!-- TWEAKS_START -->/,/<!-- TWEAKS_END -->/{//!d;}' index.html 2>/dev/null || sed -i '' '/<!-- TWEAKS_START -->/,/<!-- TWEAKS_END -->/{//!d;}' index.html

# 2. Rebuild the list array manually file-by-file from the physical disk structure
HTML_LIST=""

for deb_file in ./debs/*.deb; do
    # Skip loop iteration if no .deb files exist safely
    [ -e "$deb_file" ] || continue
    
    # Safely extract package configuration elements directly from the binary control fields
    TWEAK_ID=$(dpkg-deb -f "$deb_file" Package 2>/dev/null | tr -d '\r' | xargs)
    TWEAK_NAME=$(dpkg-deb -f "$deb_file" Name 2>/dev/null | tr -d '\r' | xargs)
    TWEAK_VERSION=$(dpkg-deb -f "$deb_file" Version 2>/dev/null | tr -d '\r' | xargs)
    TWEAK_DESC=$(dpkg-deb -f "$deb_file" Description 2>/dev/null | tr -d '\r' | xargs)
    
    # Fallbacks if properties are absent
    if [ -z "$TWEAK_NAME" ]; then TWEAK_NAME="$TWEAK_ID"; fi
    if [ -z "$TWEAK_DESC" ]; then TWEAK_DESC="No description provided."; fi
    
    # Extract only the file name
    CLEAN_FILENAME=$(basename "$deb_file")
    
    # CRITICAL FIX: Force the path to include your repository name explicitly
    FINAL_WEB_URL="/repo/debs/$CLEAN_FILENAME"
    
    # Append the item layout template snippet
    HTML_ITEM=$(cat <<EOF
        <li class="ios-item">
            <a href="${FINAL_WEB_URL}" style="text-decoration:none; color:inherit; display:block;">
                <span class="right-align"><span class="chevron"></span></span>
                <div style="font-weight: bold; color: #000000;">${TWEAK_NAME} <span style="font-size:11px; color:#8e8e93;">v${TWEAK_VERSION}</span></div>
                <div class="tweak-desc">${TWEAK_DESC}</div>
            </a>
        </li>
EOF
)
    HTML_LIST="$HTML_LIST"$'\n'"$HTML_ITEM"
done

# 3. Inject the clean absolute HTML structures directly into index.html
awk -v r="$HTML_LIST" '
  /<!-- TWEAKS_START -->/ { print; print r; next }
  1
' index.html > index.tmp && mv index.tmp index.html

rm -f index.tmp index.html.bak


# ==============================================================================
# AUTOMATIC GIT CASE-SENSITIVITY RESET (PREVENTS FUTURE 404s)
# ==============================================================================
echo "Resetting Git case tracking cache to prevent 404 errors..."
git rm -r --cached debs/ 2>/dev/null
mv debs debs_temp 2>/dev/null
mv debs_temp debs 2>/dev/null
git add debs/

# ==============================================================================
# DYNAMIC COMMIT MESSAGE GENERATION
# ==============================================================================
echo "Generating dynamic commit message..."

# Check git status for changed filenames inside the debs folder
CHANGED_FILES=$(git status --porcelain debs/ | awk '{print $2}' | xargs -I {} basename {})

if [ -z "$CHANGED_FILES" ]; then
    COMMIT_MSG="Update Cydia repository structure and indices"
else
    CLEAN_LIST=$(echo "$CHANGED_FILES" | paste -sd ", " -)
    COMMIT_MSG="Repo Update: Modified packages ($CLEAN_LIST)"
fi

# Automatically sync files directly into GitHub tracking tree
echo "Syncing changes to GitHub repository..."
git add .
git commit -m "$COMMIT_MSG"
git push origin v2

echo "Done! The web routing path has been forced to include your repository subfolder."
