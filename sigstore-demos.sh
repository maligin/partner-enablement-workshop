#!/bin/bash

# Sigstore/Cosign Demo Script for Container Image Signing
# This script demonstrates signing and verifying container images using Cosign

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

signed_images=()
signing_failed=()

for image in "${pushed_images[@]}"; do
    print_color "$BLUE" "Signing: $image"
    
    # Sign the image using local keys (no OIDC)
    if COSIGN_PASSWORD="" cosign sign \
        --key "$COSIGN_KEY_DIR/cosign.key" \
        --tlog-upload=false \
        "$image" >/dev/null 2>&1; then
        
        print_color "$GREEN" "  ✅ Signed successfully"
        signed_images+=("$image")
        
        # Also get and sign by digest
        digest=$(docker inspect --format='{{index .RepoDigests 0}}' "$image" | cut -d'@' -f2)
        if [ -n "$digest" ]; then
            image_with_digest="${image%:*}@${digest}"
            print_color "$BLUE" "  📌 Also signing digest: $digest"
            
            if COSIGN_PASSWORD="" cosign sign \
                --key "$COSIGN_KEY_DIR/cosign.key" \
                --tlog-upload=false \
                "$image_with_digest" >/dev/null 2>&1; then
                print_color "$GREEN" "    ✅ Digest signed"
            fi
        fi
    else
        print_color "$RED" "  ❌ Failed to sign: $image"
        signing_failed+=("$image")
    fi
done

# Step 7: Verify signatures
print_section "7. VERIFYING SIGNATURES"

verification_passed=()
verification_failed=()

for image in "${signed_images[@]}"; do
    print_color "$BLUE" "Verifying: $image"
    
    # Verify signature
    if COSIGN_EXPERIMENTAL=0 cosign verify \
        --key "$COSIGN_KEY_DIR/cosign.pub" \
        --insecure-ignore-tlog \
        "$image" >/dev/null 2>&1; then
        
        print_color "$GREEN" "  ✅ Signature verified"
        verification_passed+=("$image")
        
        # Also verify by digest
        digest=$(docker inspect --format='{{index .RepoDigests 0}}' "$image" | cut -d'@' -f2)
        if [ -n "$digest" ]; then
            image_with_digest="${image%:*}@${digest}"
            print_color "$BLUE" "  📌 Verifying digest: $digest"
            
            if COSIGN_EXPERIMENTAL=0 cosign verify \
                --key "$COSIGN_KEY_DIR/cosign.pub" \
                --insecure-ignore-tlog \
                "$image_with_digest" >/dev/null 2>&1; then
                print_color "$GREEN" "    ✅ Digest signature verified"
            fi
        fi
    else
        print_color "$RED" "  ❌ Signature verification failed: $image"
        verification_failed+=("$image")
    fi
done

# Step 8: Display detailed signature information for one image
if [ ${#signed_images[@]} -gt 0 ]; then
    print_section "8. DETAILED SIGNATURE INFORMATION"
    
    sample_image="${signed_images[0]}"
    print_color "$BLUE" "Showing detailed info for: $sample_image"
    echo ""
    
    COSIGN_EXPERIMENTAL=0 cosign verify \
        --key "$COSIGN_KEY_DIR/cosign.pub" \
        --insecure-ignore-tlog \
        "$sample_image" 2>/dev/null | jq '.'
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
echo "curl -s http://localhost:5000/v2/_catalog | jq"
echo ""
echo "# Get tags for a specific image:"
echo "curl -s http://localhost:5000/v2/hello-go/tags/list | jq"
echo ""
echo "# Verify a specific image:"
echo "COSIGN_EXPERIMENTAL=0 cosign verify --key $COSIGN_KEY_DIR/cosign.pub --insecure-ignore-tlog $LOCAL_REGISTRY/hello-go:alpine-latest"
echo ""
echo "# Verify and show certificate details:"
echo "COSIGN_EXPERIMENTAL=0 cosign verify --key $COSIGN_KEY_DIR/cosign.pub --insecure-ignore-tlog $LOCAL_REGISTRY/hello-go:alpine-latest | jq '.'"
echo ""
echo "# Sign with annotations:"
echo "COSIGN_PASSWORD=\"\" cosign sign --key $COSIGN_KEY_DIR/cosign.key --tlog-upload=false -a \"env=dev\" -a \"team=platform\" $LOCAL_REGISTRY/hello-go:alpine-latest"
echo ""
echo "# Generate SBOM and attach:"
echo "syft $LOCAL_REGISTRY/hello-go:alpine-latest -o spdx-json > sbom.json"
echo "COSIGN_PASSWORD=\"\" cosign attach sbom --sbom sbom.json $LOCAL_REGISTRY/hello-go:alpine-latest"
echo ""

# Cleanup option
print_section "11. CLEANUP"

echo "🧹 To clean up after the demo, run:"
echo ""
echo "# Stop and remove registry:"
echo "docker stop $REGISTRY_NAME && docker rm $REGISTRY_NAME"
echo ""
echo "# Remove keys (careful!):"
echo "rm -rf $COSIGN_KEY_DIR"
echo ""
echo "# Remove images file:"
echo "rm -f $IMAGES_FILE"
echo ""

print_color "$GREEN" "✅ Demo completed successfully!"
