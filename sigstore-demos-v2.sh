#!/bin/bash

# Sigstore/Cosign Demo Script for Container Image Signing
# This script demonstrates signing and verifying container images using Cosign

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
LOCAL_REGISTRY="localhost:5000"
REGISTRY_NAME="sigstore-registry"
COSIGN_KEY_DIR="./cosign-keys"
IMAGES_FILE="images-sigstore.txt"

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print section headers
print_section() {
    echo ""
    print_color "$BLUE" "========================================"
    print_color "$BLUE" "$1"
    print_color "$BLUE" "========================================"
    echo ""
}

# Function to print command being executed
print_command() {
    print_color "$CYAN" "📟 COMMAND: $1"
    echo ""
}

# Function to check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_color "$RED" "❌ $1 is not installed. Please install it first."
        exit 1
    fi
}

# Create images list file
create_images_file() {
    cat > "$IMAGES_FILE" << 'EOF'
hello-go:alpine-latest
hello-go:alpine-latest-ms
hello-go:debian-latest
hello-go:debian-latest-ms
hello-go:ubuntu-latest
hello-go:ubuntu-latest-ms
hello-go:wolfi-latest
hello-go:wolfi-latest-apko-dev-arm64
hello-go:wolfi-latest-apko-prod-arm64
hello-go:wolfi-latest-ms
EOF
    print_color "$GREEN" "✅ Created $IMAGES_FILE with image list"
}

# Step 1: Prerequisites check
print_section "1. CHECKING PREREQUISITES"

check_command "docker"
check_command "cosign"

print_color "$GREEN" "✅ All prerequisites installed"
echo "Cosign version:"
cosign version

# Step 2: Setup local registry
print_section "2. SETTING UP LOCAL REGISTRY"

# Check if registry is already running
if docker ps | grep -q "$REGISTRY_NAME"; then
    print_color "$YELLOW" "⚠️  Registry already running, removing it..."
    docker stop "$REGISTRY_NAME" >/dev/null 2>&1
    docker rm "$REGISTRY_NAME" >/dev/null 2>&1
fi

# Start local registry
print_color "$BLUE" "Starting local registry on port 5000..."
docker run -d \
    --name "$REGISTRY_NAME" \
    --restart=always \
    -p 5000:5000 \
    registry:2

# Wait for registry to be ready
sleep 3

# Test registry
if curl -s http://localhost:5000/v2/ | grep -q '{}'; then
    print_color "$GREEN" "✅ Local registry is running at $LOCAL_REGISTRY"
else
    print_color "$RED" "❌ Failed to start local registry"
    exit 1
fi

# Step 3: Generate Cosign keys
print_section "3. GENERATING COSIGN KEYS"

# Create keys directory
mkdir -p "$COSIGN_KEY_DIR"

# Check if keys already exist
if [ -f "$COSIGN_KEY_DIR/cosign.key" ] && [ -f "$COSIGN_KEY_DIR/cosign.pub" ]; then
    print_color "$YELLOW" "⚠️  Cosign keys already exist, reusing them..."
else
    print_color "$BLUE" "Generating new Cosign key pair..."
    # Generate keys without password for demo purposes
    COSIGN_PASSWORD="" cosign generate-key-pair --output-key-prefix "$COSIGN_KEY_DIR/cosign"
    print_color "$GREEN" "✅ Keys generated in $COSIGN_KEY_DIR/"
fi

echo ""
print_color "$MAGENTA" "🔑 Public key content:"
cat "$COSIGN_KEY_DIR/cosign.pub"

# Step 4: Create and read images list
print_section "4. PREPARING IMAGES LIST"

create_images_file

# Read images from file
mapfile -t IMAGES < <(grep -v '^#' "$IMAGES_FILE" | grep -v '^$')
print_color "$GREEN" "✅ Found ${#IMAGES[@]} images to process"

# Step 5: Tag and push images to local registry
print_section "5. PUSHING IMAGES TO LOCAL REGISTRY"

pushed_images=()
failed_images=()

for image in "${IMAGES[@]}"; do
    local_image="$LOCAL_REGISTRY/$image"
    
    print_color "$BLUE" "Processing: $image"
    
    # Check if source image exists
    if docker image inspect "$image" >/dev/null 2>&1; then
        # Tag for local registry
        docker tag "$image" "$local_image"
        
        # Push to local registry
        if docker push "$local_image" >/dev/null 2>&1; then
            print_color "$GREEN" "  ✅ Pushed: $local_image"
            pushed_images+=("$local_image")
        else
            print_color "$RED" "  ❌ Failed to push: $local_image"
            failed_images+=("$image")
        fi
    else
        print_color "$YELLOW" "  ⚠️  Image not found locally: $image"
        failed_images+=("$image")
    fi
done

# Step 6: Sign images with Cosign
print_section "6. SIGNING IMAGES WITH COSIGN"

# Educational message about digest vs tag signing
print_color "$YELLOW" "⚠️  IMPORTANT: Why We Sign by Digest, Not by Tag"
echo ""
print_color "$RED" "❌ BAD PRACTICE: Signing by tag (e.g., alpine:latest)"
echo "   • Tags are MUTABLE - they can be moved to different images"
echo "   • You might sign one image, but the tag could point to another later"
echo "   • This creates security vulnerabilities in your supply chain"
echo ""
print_color "$GREEN" "✅ BEST PRACTICE: Signing by digest (e.g., alpine@sha256:abc123...)"
echo "   • Digests are IMMUTABLE - they uniquely identify an exact image"
echo "   • Cryptographically guaranteed to always refer to the same content"
echo "   • Provides true supply chain security and reproducibility"
echo ""
print_color "$YELLOW" "📝 Note: Cosign will remove tag-based signing in a future release!"
echo ""
print_color "$CYAN" "Press any key to continue with the demo..."
read -n 1 -s -r
echo ""

signed_images=()
signing_failed=()

for image in "${pushed_images[@]}"; do
    echo ""
    print_color "$MAGENTA" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$BLUE" "🖊️  Processing: $image"
    
    # First, get the digest for this image
    digest=$(docker inspect --format='{{index .RepoDigests 0}}' "$image" | cut -d'@' -f2)
    
    if [ -z "$digest" ]; then
        print_color "$RED" "❌ Could not get digest for: $image"
        signing_failed+=("$image")
        continue
    fi
    
    # Build the image reference with digest
    image_with_digest="${image%:*}@${digest}"
    
    print_color "$BLUE" "📌 Image tag: ${image#*/}"
    print_color "$GREEN" "🔒 Image digest: $digest"
    echo ""
    print_color "$BLUE" "Signing by digest: $image_with_digest"
    
    # Display the command being run
    cmd="COSIGN_PASSWORD=\"\" cosign sign --key $COSIGN_KEY_DIR/cosign.key --tlog-upload=false $image_with_digest"
    print_command "$cmd"
    
    # Sign the image by digest only
    if COSIGN_PASSWORD="" cosign sign \
        --key "$COSIGN_KEY_DIR/cosign.key" \
        --tlog-upload=false \
        "$image_with_digest"; then
        
        print_color "$GREEN" "✅ Image signed successfully by digest"
        signed_images+=("$image")
    else
        print_color "$RED" "❌ Failed to sign: $image_with_digest"
        signing_failed+=("$image")
    fi
    echo ""
done

# Step 7: Verify signatures
print_section "7. VERIFYING SIGNATURES"

verification_passed=()
verification_failed=()

for image in "${signed_images[@]}"; do
    echo ""
    print_color "$MAGENTA" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_color "$BLUE" "🔍 Verifying signature for: $image"
    
    # Get the digest for this image
    digest=$(docker inspect --format='{{index .RepoDigests 0}}' "$image" | cut -d'@' -f2)
    
    if [ -z "$digest" ]; then
        print_color "$RED" "❌ Could not get digest for verification: $image"
        verification_failed+=("$image")
        continue
    fi
    
    # Build the image reference with digest
    image_with_digest="${image%:*}@${digest}"
    
    print_color "$BLUE" "📌 Verifying digest-based signature"
    print_color "$GREEN" "🔒 Digest: $digest"
    echo ""
    
    # Display the command being run
    cmd="COSIGN_EXPERIMENTAL=0 cosign verify --key $COSIGN_KEY_DIR/cosign.pub --insecure-ignore-tlog $image_with_digest"
    print_command "$cmd"
    
    # Verify signature by digest - show output
    if COSIGN_EXPERIMENTAL=0 cosign verify \
        --key "$COSIGN_KEY_DIR/cosign.pub" \
        --insecure-ignore-tlog \
        "$image_with_digest" 2>&1; then
        
        print_color "$GREEN" "✅ Signature verification passed for digest"
        verification_passed+=("$image")
        
        # Show that tag-based verification also works (but explain it's checking the digest)
        echo ""
        print_color "$YELLOW" "ℹ️  Note: You can also verify using the tag, which resolves to the digest:"
        cmd="COSIGN_EXPERIMENTAL=0 cosign verify --key $COSIGN_KEY_DIR/cosign.pub --insecure-ignore-tlog $image"
        print_command "$cmd"
        
        if COSIGN_EXPERIMENTAL=0 cosign verify \
            --key "$COSIGN_KEY_DIR/cosign.pub" \
            --insecure-ignore-tlog \
            "$image" 2>&1 | head -5; then
            print_color "$GREEN" "✅ Tag-based verification also works (resolves to same digest)"
        fi
    else
        print_color "$RED" "❌ Signature verification failed: $image_with_digest"
        verification_failed+=("$image")
    fi
    echo ""
done

# Step 8: Display detailed signature information for one image with JSON formatting
if [ ${#signed_images[@]} -gt 0 ]; then
    print_section "8. DETAILED SIGNATURE INFORMATION (JSON)"
    
    sample_image="${signed_images[0]}"
    
    # Get digest for the sample image
    digest=$(docker inspect --format='{{index .RepoDigests 0}}' "$sample_image" | cut -d'@' -f2)
    image_with_digest="${sample_image%:*}@${digest}"
    
    print_color "$BLUE" "Showing JSON-formatted signature info for:"
    print_color "$GREEN" "  Tag: $sample_image"
    print_color "$GREEN" "  Digest: $image_with_digest"
    echo ""
    
    cmd="COSIGN_EXPERIMENTAL=0 cosign verify --key $COSIGN_KEY_DIR/cosign.pub --insecure-ignore-tlog $image_with_digest | jq '.'"
    print_command "$cmd"
    
    COSIGN_EXPERIMENTAL=0 cosign verify \
        --key "$COSIGN_KEY_DIR/cosign.pub" \
        --insecure-ignore-tlog \
        "$image_with_digest" 2>/dev/null | jq '.'
fi

# Optional: Demonstrate why tag signing is problematic
print_section "8a. DEMONSTRATION: Why NOT to Sign by Tag (Optional)"

print_color "$YELLOW" "Would you like to see a demonstration of why tag-based signing is problematic? (y/N)"
read -n 1 -s -r demo_response
echo ""

if [[ $demo_response =~ ^[Yy]$ ]] && [ ${#signed_images[@]} -gt 0 ]; then
    demo_image="${signed_images[0]}"
    
    print_color "$RED" "🚨 DEMONSTRATION: The Problem with Tag-Based Signing"
    echo ""
    print_color "$YELLOW" "Let's try to sign by tag and see the warning:"
    echo ""
    
    cmd="COSIGN_PASSWORD=\"\" cosign sign --key $COSIGN_KEY_DIR/cosign.key --tlog-upload=false $demo_image"
    print_command "$cmd"
    
    print_color "$RED" "Expected output (showing why this is bad):"
    COSIGN_PASSWORD="" cosign sign \
        --key "$COSIGN_KEY_DIR/cosign.key" \
        --tlog-upload=false \
        "$demo_image" 2>&1 | grep -A 5 "WARNING" || echo "WARNING message would appear here about tag vs digest"
    
    echo ""
    print_color "$YELLOW" "☝️  As you can see, Cosign warns us that:"
    echo "   1. Tags are mutable and can change"
    echo "   2. We might sign a different image than intended"
    echo "   3. This feature will be removed in future Cosign versions"
    echo ""
    print_color "$GREEN" "That's why we only sign by digest in production! ✅"
    echo ""
    print_color "$CYAN" "Press any key to continue..."
    read -n 1 -s -r
fi

# Step 9: Summary
print_section "9. SUMMARY"

echo "📊 RESULTS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  Total images:        %2d\n" "${#IMAGES[@]}"
printf "  Pushed to registry:  %2d\n" "${#pushed_images[@]}"
printf "  Successfully signed: %2d\n" "${#signed_images[@]}"
printf "  Verified signatures: %2d\n" "${#verification_passed[@]}"

if [ ${#failed_images[@]} -gt 0 ]; then
    echo ""
    print_color "$YELLOW" "⚠️  IMAGES NOT FOUND:"
    for img in "${failed_images[@]}"; do
        echo "  - $img"
    done
fi

if [ ${#signing_failed[@]} -gt 0 ]; then
    echo ""
    print_color "$RED" "❌ SIGNING FAILED:"
    for img in "${signing_failed[@]}"; do
        echo "  - $img"
    done
fi

if [ ${#verification_failed[@]} -gt 0 ]; then
    echo ""
    print_color "$RED" "❌ VERIFICATION FAILED:"
    for img in "${verification_failed[@]}"; do
        echo "  - $img"
    done
fi

# Step 10: Useful commands
print_section "10. USEFUL COMMANDS"

echo "🔧 Try these commands:"
echo ""
echo "# List images in local registry:"
print_color "$CYAN" "curl -s http://localhost:5000/v2/_catalog | jq"
echo ""
echo "# Get tags for a specific image:"
print_color "$CYAN" "curl -s http://localhost:5000/v2/hello-go/tags/list | jq"
echo ""
echo "# Get digest for an image:"
print_color "$CYAN" "docker inspect --format='{{index .RepoDigests 0}}' $LOCAL_REGISTRY/hello-go:alpine-latest"
echo ""
echo "# Sign by digest (BEST PRACTICE):"
print_color "$CYAN" "COSIGN_PASSWORD=\"\" cosign sign --key $COSIGN_KEY_DIR/cosign.key --tlog-upload=false $LOCAL_REGISTRY/hello-go@sha256:YOUR_DIGEST_HERE"
echo ""
echo "# Verify by digest (BEST PRACTICE):"
print_color "$CYAN" "COSIGN_EXPERIMENTAL=0 cosign verify --key $COSIGN_KEY_DIR/cosign.pub --insecure-ignore-tlog $LOCAL_REGISTRY/hello-go@sha256:YOUR_DIGEST_HERE"
echo ""
echo "# Verify and show signature details:"
print_color "$CYAN" "COSIGN_EXPERIMENTAL=0 cosign verify --key $COSIGN_KEY_DIR/cosign.pub --insecure-ignore-tlog $LOCAL_REGISTRY/hello-go@sha256:YOUR_DIGEST_HERE | jq '.'"
echo ""
echo "# Sign with annotations (always use digest!):"
print_color "$CYAN" "COSIGN_PASSWORD=\"\" cosign sign --key $COSIGN_KEY_DIR/cosign.key --tlog-upload=false -a \"env=dev\" -a \"team=platform\" $LOCAL_REGISTRY/hello-go@sha256:YOUR_DIGEST_HERE"
echo ""
echo "# Generate SBOM and attach (use digest!):"
print_color "$CYAN" "syft $LOCAL_REGISTRY/hello-go@sha256:YOUR_DIGEST_HERE -o spdx-json > sbom.json"
print_color "$CYAN" "COSIGN_PASSWORD=\"\" cosign attach sbom --sbom sbom.json $LOCAL_REGISTRY/hello-go@sha256:YOUR_DIGEST_HERE"
echo ""
echo "# Verify with annotations:"
print_color "$CYAN" "COSIGN_EXPERIMENTAL=0 cosign verify --key $COSIGN_KEY_DIR/cosign.pub --insecure-ignore-tlog -a env=dev $LOCAL_REGISTRY/hello-go@sha256:YOUR_DIGEST_HERE"
echo ""

# Cleanup option
print_section "11. CLEANUP"

echo "🧹 To clean up after the demo, run:"
echo ""
echo "# Stop and remove registry:"
print_color "$CYAN" "docker stop $REGISTRY_NAME && docker rm $REGISTRY_NAME"
echo ""
echo "# Remove keys (careful!):"
print_color "$CYAN" "rm -rf $COSIGN_KEY_DIR"
echo ""
echo "# Remove images file:"
print_color "$CYAN" "rm -f $IMAGES_FILE"
echo ""

print_color "$GREEN" "✅ Demo completed successfully!"
