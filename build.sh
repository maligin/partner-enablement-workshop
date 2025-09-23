#!/bin/bash

GIT_REPO="https://github.com/maligin/partner-enablement-workshop.git"
export GIT_REPO

set -e

# Detect host architecture
detect_arch() {
    case $(uname -m) in
        x86_64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        *)
            echo "$(uname -m)"
            ;;
    esac
}

ARCH=$(detect_arch)

clean_all() {
    docker image rm -f $(docker image ls | grep hello-go | awk '{ print $3 }')
}

build_ubuntu() {
    docker buildx build -t hello-go:ubuntu-latest -f dockerfiles/Dockerfile.ubuntu .
}
build_ubuntu_ms() {
    docker buildx build -t hello-go:ubuntu-latest-ms -f dockerfiles/Dockerfile.ubuntu-ms .
}
build_debian() {
    docker buildx build -t hello-go:debian-latest -f dockerfiles/Dockerfile.debian .
}
build_debian_ms() {
    docker buildx build -t hello-go:debian-latest-ms -f dockerfiles/Dockerfile.debian-ms .
}
build_alpine() {
    docker buildx build -t hello-go:alpine-latest -f dockerfiles/Dockerfile.alpine .
}
build_alpine_ms() {
    docker buildx build -t hello-go:alpine-latest-ms -f dockerfiles/Dockerfile.alpine-ms .
}
build_wolfi() {
    docker buildx build -t hello-go:wolfi-latest -f dockerfiles/Dockerfile.wolfi .
}
build_wolfi_ms() {
    docker buildx build -t hello-go:wolfi-latest-ms -f dockerfiles/Dockerfile.wolfi-ms .
}

move_sbom_files() {
    local prefix=$1
    
    # Move index SBOM if it exists
    if [[ -f sbom-index.spdx.json ]]; then
        mv sbom-index.spdx.json "apko-images/${prefix}-sbom-index.spdx.json"
        echo "Moved sbom-index.spdx.json to apko-images/${prefix}-sbom-index.spdx.json"
    else
        echo "Warning: sbom-index.spdx.json not found"
    fi
    
    # Move architecture-specific SBOM if it exists
    local arch_sbom="sbom-${ARCH}.spdx.json"
    if [[ -f "$arch_sbom" ]]; then
        mv "$arch_sbom" "apko-images/${prefix}-sbom-${ARCH}.spdx.json"
        echo "Moved $arch_sbom to apko-images/${prefix}-sbom-${ARCH}.spdx.json"
    else
        echo "Warning: $arch_sbom not found"
        # List available SBOM files for debugging
        echo "Available SBOM files:"
        ls -la sbom-*.spdx.json 2>/dev/null || echo "No SBOM files found"
    fi
}

build_apko_dev() {
    ./update-sha256-melange.sh
    mkdir -p ./apko-images
    
    if [[ ! -f melange.rsa || ! -f melange.rsa.pub ]]; then
        echo "melange.rsa oder melange.rsa.pub fehlt, erstelle Keypair..."
        melange keygen
    else
        echo "melange.rsa und melange.rsa.pub sind bereits vorhanden."
    fi
    
    echo "Building for architecture: $ARCH"
    melange build melange/melange.yaml --arch host --signing-key melange.rsa --git-repo-url=$GIT_REPO
    apko build apko/apko-dev.yaml hello-go:wolfi-latest-apko-dev apko-images/hello-go-dev.tar --arch host
    
    # Move SBOM files with better error handling
    move_sbom_files "hello-go-dev"
    
    docker load < apko-images/hello-go-dev.tar
}

build_apko_prod() {
    ./update-sha256-melange.sh
    mkdir -p ./apko-images
    
    if [[ ! -f melange.rsa || ! -f melange.rsa.pub ]]; then
        echo "melange.rsa oder melange.rsa.pub fehlt, erstelle Keypair..."
        melange keygen
    else
        echo "melange.rsa und melange.rsa.pub sind bereits vorhanden."
    fi
    
    echo "Building for architecture: $ARCH"
    melange build melange/melange.yaml --arch host --signing-key melange.rsa --git-repo-url=$GIT_REPO
    apko build apko/apko-prod.yaml hello-go:wolfi-latest-apko-prod apko-images/hello-go-prod.tar --arch host
    
    # Move SBOM files with better error handling
    move_sbom_files "hello-go-prod"
    
    docker load < apko-images/hello-go-prod.tar
}

build_all() {
    build_ubuntu
    build_ubuntu_ms
    build_debian
    build_debian_ms
    build_alpine
    build_alpine_ms
    build_wolfi
    build_wolfi_ms
    build_apko_dev
    build_apko_prod
    list_images
}

# Scanning functions
get_display_name() {
    local image=$1
    echo "$image" | sed 's/hello-go://'
}

scan_with_grype() {
    local image=$1
    local safe_name=$(echo "$image" | tr '/:' '_')
    local output_dir="scan-results"
    
    mkdir -p "$output_dir"
    
    # Run grype scan and save detailed output
    grype "$image" -o table > "$output_dir/grype_${safe_name}_detailed.txt" 2>/dev/null || {
        echo "  ❌ Scan failed for $image"
        return 1
    }
    
    # Run grype scan in JSON format for easier parsing
    grype "$image" -o json > "$output_dir/grype_${safe_name}.json" 2>/dev/null || {
        echo "  ❌ JSON scan failed for $image"
        return 1
    }
    
    # Parse JSON to count vulnerabilities by severity
    if [ -f "$output_dir/grype_${safe_name}.json" ]; then
        python3 -c "
import json
import sys

try:
    with open('$output_dir/grype_${safe_name}.json', 'r') as f:
        data = json.load(f)
    
    # Count vulnerabilities by severity
    severities = {'Critical': 0, 'High': 0, 'Medium': 0, 'Low': 0, 'Unknown': 0, 'Negligible': 0}
    total = 0
    
    if 'matches' in data:
        for match in data['matches']:
            severity = match.get('vulnerability', {}).get('severity', 'Unknown')
            if severity in severities:
                severities[severity] += 1
            elif severity == 'Negligible':
                severities['Negligible'] += 1
            else:
                severities['Unknown'] += 1
            total += 1
    
    # Combine Unknown and Negligible as 'Other'
    other = severities['Unknown'] + severities['Negligible']
    
    # Output: total,critical,high,medium,low,other
    print(f\"{total},{severities['Critical']},{severities['High']},{severities['Medium']},{severities['Low']},{other}\")
    
except Exception as e:
    print('0,0,0,0,0,0')
    print(f'Error parsing JSON: {e}', file=sys.stderr)
" > "$output_dir/grype_${safe_name}_counts.txt"
    else
        echo "0,0,0,0,0,0" > "$output_dir/grype_${safe_name}_counts.txt"
    fi
}

display_scan_results() {
    local output_dir="scan-results"
    
    # Get list of scanned images
    local images=$(docker image ls | grep hello-go | awk '{print $1":"$2}' | sort)
    
    if [ -z "$images" ]; then
        echo "No hello-go images found to display results for."
        return 1
    fi
    
    echo ""
    echo "================================================================================================="
    echo "                                VULNERABILITY SCAN RESULTS"
    echo "================================================================================================="
    echo ""
    echo "Scanner: Grype - All severities included (Critical, High, Medium, Low, Unknown/Negligible)"
    echo ""
    
    # Table header
    printf "%-30s %-8s %-8s %-10s %-6s %-8s %-6s %-7s %-25s\n" \
        "Image" "Scanner" "Total" "Critical" "High" "Medium" "Low" "Other" "Notes"
    printf "%-30s %-8s %-8s %-10s %-6s %-8s %-6s %-7s %-25s\n" \
        "------------------------------" "--------" "--------" "----------" "------" "--------" "------" "-------" "-------------------------"
    
    # Process each image
    for image in $images; do
        local safe_name=$(echo "$image" | tr '/:' '_')
        local display_name=$(get_display_name "$image")
        
        # Check if we have grype results
        if [ -f "$output_dir/grype_${safe_name}_counts.txt" ]; then
            local grype_data=$(cat "$output_dir/grype_${safe_name}_counts.txt")
            local total_g=$(echo "$grype_data" | cut -d',' -f1)
            local crit_g=$(echo "$grype_data" | cut -d',' -f2)
            local high_g=$(echo "$grype_data" | cut -d',' -f3)
            local med_g=$(echo "$grype_data" | cut -d',' -f4)
            local low_g=$(echo "$grype_data" | cut -d',' -f5)
            local other_g=$(echo "$grype_data" | cut -d',' -f6)
            
            # Add note for specific image types
            local notes=""
            case "$display_name" in
                *"alpine"*) notes="Alpine-based image" ;;
                *"ubuntu"*) notes="Ubuntu-based image" ;;
                *"debian"*) notes="Debian-based image" ;;
                *"wolfi"*) notes="Wolfi-based image" ;;
                *"apko"*) notes="Apko-built minimal image" ;;
            esac
            
            printf "%-30s %-8s %-8s %-10s %-6s %-8s %-6s %-7s %-25s\n" \
                "$display_name" "Grype" "$total_g" "$crit_g" "$high_g" "$med_g" "$low_g" "$other_g" "$notes"
        else
            printf "%-30s %-8s %-8s %-10s %-6s %-8s %-6s %-7s %-25s\n" \
                "$display_name" "Grype" "N/A" "N/A" "N/A" "N/A" "N/A" "N/A" "Scan failed"
        fi
    done
    
    echo ""
    echo "================================================================================================="
    echo ""
    echo "KEY OBSERVATIONS:"
    echo ""
    echo "🔍 SCANNER CHARACTERISTICS:"
    echo "   • Comprehensive Detection: Reports all known vulnerabilities regardless of fix availability"
    echo "   • Broad CVE Coverage: Extensive vulnerability database coverage"
    echo "   • Pattern Matching: Uses multiple matching strategies for vulnerability detection"
    echo "   • Consistent Results: Generally consistent vulnerability detection across distributions"
    echo ""
    echo "📊 IMAGE ANALYSIS:"
    echo "   • Alpine images: Typically show fewer vulnerabilities due to minimal base"
    echo "   • Wolfi/Chainguard images: Mostly zero CVEs due to reproducible and declarative build process from source using apko and melange"
    echo "   • Ubuntu/Debian images: May show more vulnerabilities due to larger package sets"
    echo "   • Multi-stage builds (*-ms): Should show reduced attack surface"
    echo "   • Apko-built images: Minimal distroless images with security-first approach"
    echo ""
    echo "🛡️  SECURITY RECOMMENDATIONS:"
    echo "   1. Critical/High Severity: Address these vulnerabilities immediately"
    echo "   2. Medium/Low Severity: Consider for regular maintenance cycles"
    echo "   3. Base Image Choice: Consider Wolfi or Alpine for security-sensitive applications"
    echo "   4. Multi-stage Builds: Prefer multi-stage builds to reduce attack surface"
    echo ""
}

generate_scan_report() {
    local output_dir="scan-results"
    local report_file="$output_dir/vulnerability_scan_report.md"
    
    echo "📄 Generating detailed markdown report..."
    
    # Get list of scanned images
    local images=$(docker image ls | grep hello-go | awk '{print $1":"$2}' | sort)
    
    if [ -z "$images" ]; then
        echo "No hello-go images found to report on."
        return 1
    fi
    
    cat > "$report_file" << EOF
# Container Vulnerability Scan Report

This report shows vulnerability detection results using Grype across different base images.
**All severities included (Critical, High, Medium, Low, Unknown/Negligible).**

Generated on: $(date)

## Scanner Information

### Grype Characteristics:
- **Comprehensive Detection**: Reports all known vulnerabilities regardless of fix availability
- **Broad CVE Coverage**: Extensive vulnerability database coverage  
- **Pattern Matching**: Uses multiple matching strategies for vulnerability detection
- **Consistent Results**: Generally consistent vulnerability detection across distributions

## Scan Results Summary

| Image | Scanner | Total | Critical | High | Medium | Low | Other | Notes |
|-------|---------|-------|----------|------|--------|-----|-------|-------|
EOF

    # Process each image
    for image in $images; do
        local safe_name=$(echo "$image" | tr '/:' '_')
        local display_name=$(get_display_name "$image")
        
        # Check if we have grype results
        if [ -f "$output_dir/grype_${safe_name}_counts.txt" ]; then
            local grype_data=$(cat "$output_dir/grype_${safe_name}_counts.txt")
            local total_g=$(echo "$grype_data" | cut -d',' -f1)
            local crit_g=$(echo "$grype_data" | cut -d',' -f2)
            local high_g=$(echo "$grype_data" | cut -d',' -f3)
            local med_g=$(echo "$grype_data" | cut -d',' -f4)
            local low_g=$(echo "$grype_data" | cut -d',' -f5)
            local other_g=$(echo "$grype_data" | cut -d',' -f6)
            
            # Add note for specific image types
            local notes=""
            case "$display_name" in
                *"alpine"*) notes="Alpine-based image" ;;
                *"ubuntu"*) notes="Ubuntu-based image" ;;
                *"debian"*) notes="Debian-based image" ;;
                *"wolfi"*) notes="Wolfi-based image" ;;
                *"apko"*) notes="Apko-built minimal image" ;;
            esac
            
            echo "| $display_name | Grype | $total_g | $crit_g | $high_g | $med_g | $low_g | $other_g | $notes |" >> "$report_file"
        else
            echo "| $display_name | Grype | N/A | N/A | N/A | N/A | N/A | N/A | Scan failed |" >> "$report_file"
        fi
    done
    
    # Add summary section
    cat >> "$report_file" << 'EOF'

## Summary

The table above shows vulnerability counts detected by Grype across all built container images.

### Image Analysis:
- **Alpine images**: Typically show fewer vulnerabilities due to minimal base and security-focused design
- **Wolfi/Chainguard images**: Mostly zero CVEs due to reproducible and declarative build process from source using apko and melange
- **Ubuntu/Debian images**: May show more vulnerabilities due to larger package sets
- **Multi-stage builds (*-ms)**: Should show reduced attack surface compared to single-stage builds
- **Apko-built images**: Minimal distroless images with security-first approach

### Recommendations:
1. **Critical/High Severity**: Address these vulnerabilities first through base image updates or package updates
2. **Medium/Low Severity**: Consider for regular maintenance cycles
3. **Base Image Choice**: Consider Wolfi or Alpine for security-sensitive applications
4. **Multi-stage Builds**: Prefer multi-stage builds to reduce final image size and attack surface

### Detailed Reports:
Individual detailed scan reports are available in the `scan-results/` directory:
EOF

    # List available detailed reports
    for image in $images; do
        local safe_name=$(echo "$image" | tr '/:' '_')
        local display_name=$(get_display_name "$image")
        if [ -f "$output_dir/grype_${safe_name}_detailed.txt" ]; then
            echo "- \`$display_name\`: grype_${safe_name}_detailed.txt" >> "$report_file"
        fi
    done
    
    echo "" >> "$report_file"
    echo "Report generated on: $(date)" >> "$report_file"
    
    echo "   ✅ Detailed markdown report: $report_file"
}

scan_all() {
    local images=$(docker image ls | grep hello-go | awk '{print $1":"$2}' | sort)
    
    if [ -z "$images" ]; then
        echo "No hello-go images found. Please build some images first."
        echo "Available commands: all, ubuntu, debian, alpine, wolfi, apko-dev, apko-prod"
        return 1
    fi
    
    echo "Found images to scan:"
    echo "$images"
    echo ""
    
    # Check if grype is installed
    if ! command -v grype &> /dev/null; then
        echo "Error: grype is not installed."
        echo "Please install grype: https://github.com/anchore/grype#installation"
        return 1
    fi
    
    # Check if python3 is available for JSON parsing
    if ! command -v python3 &> /dev/null; then
        echo "Error: python3 is required for parsing scan results."
        return 1
    fi
    
    echo "Starting vulnerability scans with Grype..."
    echo "This may take several minutes..."
    echo ""
    
    local scan_count=0
    local total_images=$(echo "$images" | wc -l)
    
    for image in $images; do
        scan_count=$((scan_count + 1))
        printf "[%2d/%d] 🔍 Scanning: %s\n" $scan_count $total_images "$image"
        if scan_with_grype "$image"; then
            echo "  ✅ Complete"
        fi
        echo ""
    done
    
    echo "✅ All scans completed!"
    
    # Display results in console first
    display_scan_results
    
    # Generate detailed markdown report
    generate_scan_report
    
    echo ""
    echo "📁 FILES GENERATED:"
    echo "   • Detailed markdown report: scan-results/vulnerability_scan_report.md"
    echo "   • Individual scan files: scan-results/grype_*_detailed.txt"
    echo ""
    echo "💡 To view individual detailed scans: ls scan-results/grype_*_detailed.txt"
}

list_images() {
    docker image ls | grep hello-go
}

case "$1" in
    all)        build_all ;;
    debian)     build_debian ;;
    debian-ms)  build_debian_ms ;;
    alpine)     build_alpine ;;
    alpine-ms)  build_alpine_ms ;;
    ubuntu)     build_ubuntu ;;
    ubuntu-ms)  build_ubuntu_ms ;;
    wolfi)      build_wolfi ;;
    wolfi-ms)   build_wolfi_ms ;;
    apko-dev)   build_apko_dev ;;
    apko-prod)  build_apko_prod ;;
    list)       list_images ;;
    clean)      clean_all ;;
    scan-all)   scan_all ;;
    *)
        echo "Usage: $0 {all|debian|debian-ms|alpine|alpine-ms|ubuntu|ubuntu-ms|wolfi|wolfi-ms|apko-dev|apko-prod|list|clean|scan-all}"
        exit 1
        ;;
esac
