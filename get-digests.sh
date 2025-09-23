#!/bin/bash

# Show digests for all hello-go images
echo "IMAGE DIGESTS FOR PINNING:"
echo "=========================="
echo ""

# Check if images list file exists
IMAGES_FILE="images-all.txt"
if [ ! -f "$IMAGES_FILE" ]; then
    echo "❌ Error: $IMAGES_FILE not found!"
    echo "Please create $IMAGES_FILE with one image name per line."
    exit 1
fi

# Read images from file, filtering out empty lines and comments
mapfile -t IMAGES < <(grep -v '^#' "$IMAGES_FILE" | grep -v '^$')

if [ ${#IMAGES[@]} -eq 0 ]; then
    echo "❌ Error: No images found in $IMAGES_FILE"
    exit 1
fi

echo "📋 Reading images from: $IMAGES_FILE"
echo "🔍 Found ${#IMAGES[@]} images to check"
echo ""

found_count=0
missing_count=0
missing_images=()

for image in "${IMAGES[@]}"; do
    # Check if image exists using docker images command
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${image}$"; then
        # Get image ID directly using docker images command
        id=$(docker images --format "{{.Digest}}" --filter "reference=${image}" | head -1)
        if [ -n "$id" ]; then
            echo "✅ $image@sha256:$id"
            found_count=$((found_count + 1))
        else
            echo "❌ $image - ERROR GETTING DIGEST"
            missing_count=$((missing_count + 1))
        fi
    else
        echo "❌ $image - NOT FOUND"
        missing_images+=("$image")
        missing_count=$((missing_count + 1))
    fi
done

echo ""
echo "=========================="
echo "SUMMARY:"
echo "  Found: $found_count images"
echo "  Missing: $missing_count images"

if [ $missing_count -gt 0 ]; then
    echo ""
    echo "MISSING IMAGES:"
    for missing in "${missing_images[@]}"; do
        echo "  • $missing"
    done
    echo ""
    echo "💡 To build missing images, run:"
    echo "   ./build.sh all"
    echo "💡 To update image list, edit:"
    echo "   $IMAGES_FILE"
fi
