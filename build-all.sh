#!/bin/bash
set -e

clean_all() {
    docker image rm -f $(docker image ls | grep hello-go | awk '{ print $3 }')
}

build_ubuntu() {
    docker buildx build -t hello-go:ubuntu-latest -f Dockerfile.ubuntu .
}
build_ubuntu_ms() {
    docker buildx build -t hello-go:ubuntu-latest-ms -f Dockerfile.ubuntu-ms .
}
build_debian() {
    docker buildx build -t hello-go:debian-latest -f Dockerfile.debian .
}
build_debian_ms() {
    docker buildx build -t hello-go:debian-latest-ms -f Dockerfile.debian-ms .
}
build_alpine() {
    docker buildx build -t hello-go:alpine-latest -f Dockerfile.alpine .
}
build_alpine_ms() {
    docker buildx build -t hello-go:alpine-latest-ms -f Dockerfile.alpine-ms .
}
build_wolfi() {
    docker buildx build -t hello-go:wolfi-latest -f Dockerfile.wolfi .
}
build_wolfi_ms() {
    docker buildx build -t hello-go:wolfi-latest-ms -f Dockerfile.wolfi-ms .
}

build_apko_dev() {
    ./update-sha256-melange.sh
    melange build melange.yaml --arch host --signing-key melange.rsa
    apko build apko-dev.yaml hello-go:wolfi-latest-apko-dev hello-go-dev.tar --arch host
    mv sbom-index.spdx.json hello-go-dev-sbom-index.spdx.json
    mv sbom-x86_64.spdx.json hello-go-dev-sbom-x86_64.spdx.json
    docker load < hello-go-dev.tar
    #rm -f hello-go-dev.tar
}

build_apko_prod() {
    ./update-sha256-melange.sh
    melange build melange.yaml --arch host --signing-key melange.rsa
    apko build apko-prod.yaml hello-go:wolfi-latest-apko-prod hello-go-prod.tar --arch host
    mv sbom-index.spdx.json hello-go-prod-sbom-index.spdx.json
    mv sbom-x86_64.spdx.json hello-go-prod-sbom-x86_64.spdx.json
    docker load < hello-go-prod.tar
    #rm -f hello-go-prod.tar
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
    list)	list_images ;;
    clean)	clean_all ;;
    *)
        echo "Usage: $0 {all|debian|debian-ms|alpine|alpine-ms|ubuntu|ubuntu-ms|wolfi|wolfi-ms|apko-dev|apko-prod|list|clean}"
        exit 1
        ;;
esac
