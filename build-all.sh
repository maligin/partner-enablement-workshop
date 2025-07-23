#!/bin/bash

# build Ubuntu
docker buildx build -t hello-go:ubuntu-latest -f Dockerfile.ubuntu .
docker buildx build -t hello-go:ubuntu-latest-ms -f Dockerfile.ubuntu-ms .

# build Debian
docker buildx build -t hello-go:debian-latest -f Dockerfile.debian .
docker buildx build -t hello-go:debian-latest -f Dockerfile.debian .

# build Alpine
docker buildx build -t hello-go:alpine-latest -f Dockerfile.alpine .
docker buildx build -t hello-go:alpine-latest-ms -f Dockerfile.alpine-ms .

# build Wolfi
docker buildx build -t hello-go:wolfi-latest -f Dockerfile.wolfi .
docker buildx build -t hello-go:wolfi-latest-ms -f Dockerfile.wolfi-ms .

# build Wolfi using apko + melange
## hello-go apk
./update-sha256-melange.sh
melange build melange.yaml --arch host --signing-key melange.rsa

## build containers
### dev-image
apko build apko-dev.yaml hello-go:wolfi-latest-apko-dev hello-go-dev.tar --arch host
### saving sboms
mv sbom-index.spdx.json hello-go-prod-sbom-index.spdx.json
mv sbom-x86_64.spdx.json hello-go-prod-sbom-x86_64.spdx.json

### prod-image
apko build apko-prod.yaml hello-go:wolfi-latest-apko-prod hello-go-prod.tar --arch host
### saving sboms
mv sbom-index.spdx.json hello-go-dev-sbom-index.spdx.json
mv sbom-x86_64.spdx.json hello-go-dev-sbom-x86_64.spdx.json

## load containers
docker load < hello-go-dev.tar
docker load < hello-go-prod.tar

## remove tars
#rm -rf hello-go-dev.tar hello-go-prod.tar

# list built containers
docker image ls | grep hello-go
