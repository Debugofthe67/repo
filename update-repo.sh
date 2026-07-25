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
# DYNAMIC HTML INJECTION (FIXED RELATIVE PATHS)
# ==============================================================================
echo "Updating index.html with live tweak metadata..."

# 1. Clear out any previous dynamically generated tweak lists from index.html
sed -i.bak '//,//{//!d;}' index.html 2>/dev/null || sed -i '' '//,//{//!d;}' index.html

# 2. Parse Packages file using AWK
HTML_LIST=$(awk '
BEGIN {
    RS = ""
    FS = "\n"
}
{
    id = ""
    name = ""
    desc = ""
    ver = ""
    filename = ""
    
    for (i = 1; i <= NF; i++) {
        gsub(/[\r\t]/, "", $i)
        gsub(/[[:space:]]+$/, "", $i)
        
        if ($i ~ /^Package:/) { id = $i; sub(/^Package:[[:space:]]*/, "", id) }
        if ($i ~ /^Name:/) { name = $i; sub(/^Name:[[:space:]]*/, "", name) }
        if ($i ~ /^Description:/) { desc = $i; sub(/^Description:[[:space:]]*/, "", desc) }
        if ($i ~ /^Version:/) { ver = $i; sub(/^Version:[[:space:]]*/, "", ver) }
        if ($i ~ /^Filename:/) { filename = $i; sub(/^Filename:[[:space:]]*/, "", filename) }
    }
    
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", filename)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", ver)
    
    if (id != "" && filename != "") {
        if (name == "") name = id
        if (desc == "") desc = "No description provided."
        
        if (!(id in saved_version) || ver > saved_version[id]) {
            saved_version[id] = ver
            saved_name[id] = name
            saved_desc[id] = desc
            saved_file[id] = filename
        }
    }
}
END {
    for (id in saved_version) {
        clean_url = saved_file[id]
        
        # FIX: Strip "./" so it becomes a relative path "debs/filename.deb"
        sub(/^\.\//, "", clean_url)
        
        print "        <li class=\"ios-item\">"
        print "            <a href=\"" clean_url "\" style=\"text-decoration:none; color:inherit; display:block;\">"
        print "                <span class=\"right-align\"><span class=\"chevron\"></span></span>"
        print "                <div style=\"font-weight: bold; color: #000000;\">" saved_name[id] " <span style=\"font-size:11px; color:#8e8e93;\">v" saved_version[id] "</span></div>"
        print "                <div class=\"tweak-desc\">" saved_desc[id] "</div>"
        print "            </a>"
        print "        </li>"
    }
}' Packages)

# 3. Inject into index.html
awk -v r="$HTML_LIST" '
  // { print; print r; next }
  1
' index.html > index.tmp && mv index.tmp index.html

rm -f index.tmp index.html.bak

# Force create .nojekyll so GitHub Pages doesn't block raw files
touch .nojekyll

# Reset Git case tracking cache
echo "Resetting Git case tracking cache..."
git rm -r --cached debs/ 2>/dev/null
mv debs debs_temp 2>/dev/null
mv debs_temp debs 2>/dev/null
git add debs/

# Sync changes directly into the current git branch
echo "Syncing changes to GitHub..."
git add .
git commit -m "Update repository index and fix relative links"
git push origin HEAD

echo "Done! Repository indices updated and deployed."