# hello-go: Multi-Platform Container Build Demo

This repository demonstrates **modern, secure, reproducible container builds** using both classic Dockerfile-based methods and the [apko](https://github.com/chainguard-dev/apko) / [melange](https://github.com/chainguard-dev/melange) toolchain (the foundation of [Wolfi](https://wolfi.dev/) and [Chainguard Images](https://images.chainguard.dev/)).

---

## Why Compare Dockerfile vs. apko/melange?

Traditional Dockerfiles are familiar but opaque:  
- No true build provenance  
- Hidden dependencies  
- Uncontrolled package supply chain  
- No out-of-the-box SBOM or SLSA provenance

The apko/melange approach:
- **Builds every package from source** with full traceability
- **Generates and signs SBOMs**
- Enables **distroless** images (minimal attack surface)
- Declarative, reproducible, automated — designed for modern supply chain requirements

---

## Repository Structure

| File/Folder              | Purpose                                            |
|--------------------------|----------------------------------------------------|
| `main.go`                | Sample Go app                                      |
| `go.mod`, `go.sum`       | Go dependencies                                    |
| `melange/melange.yaml`           | melange build recipe (declarative package build)   |
| `apko/apko-dev.yaml`          | apko dev image spec (distroless image)             |
| `apko/apko-prod.yaml`         | Prod variant (hardened, minimal)                   |
| `dockerfiles/Dockerfile.ubuntu`      | Classic Ubuntu-based Dockerfile                    |
| `dockerfiles/Dockerfile.ubuntu-ms`   | Ubuntu + Multistaget best practices (multistage)   |
| `dockerfiles/Dockerfile.debian-ms`   | Debian + Multistaget best practices (multistage)   |
| `dockerfiles/Dockerfile.alpine`      | Alpine-based Dockerfile                            |
| `dockerfiles/Dockerfile.alpine-ms`   | Alpine + Multistaget best practices (multistage)   |
| `dockerfiles/Dockerfile.wolfi`       | Wolfi-based Dockerfile (distroless, single-stage)  |
| `dockerfiles/Dockerfile.wolfi-ms`    | Wolfi-based multistage (build + minimal runtime)   |
| `LICENSE`                | Licensing info                                     |
| `.gitignore`             | Clean repo config                                  |

---

## Workshop Prerequisites
For this workshop you will need following tooling installed:
- git
- Docker
- cosign (optional)
- melange (optinal)
- apko (optional)
- yq
- jq

## Instructions (TL;DR):
Clone repo:
```sh
git clone git@github.com:maligin/partner-enablement-workshop.git
```

Build all (lazy-style):
```sh
./build-all.sh all
```

## Build Examples

### **1. Classic Dockerfile builds**

Each Dockerfile represents a different base OS and hardening level:

#### Single Dockerfile - based on ```ubuntu:latest```
```sh
docker buildx build -t hello-go:ubuntu-latest -f dockerfiles/Dockerfile.ubuntu .
```

#### Multi-stage build based on ```ubuntu:latest```
```sh
docker buildx build -t hello-go:ubuntu-latest-ms -f dockerfiles/Dockerfile.ubuntu-ms .
```

#### Single Dockerfile - based on ```debian:latest```
```sh
docker buildx build -t hello-go:debian-latest -f dockerfiles/Dockerfile.debian .
```

#### Multi-stage build based on ```debian:latest```
```sh
docker buildx build -t hello-go:debian-latest-ms -f dockerfiles/Dockerfile.debian-ms .
```

#### Single Dockerfile - based on ```alpine:latest```
```sh
docker buildx build -t hello-go:alpine-latest -f dockerfiles/Dockerfile.alpine .
```

#### Multi-stage build based on ```alpine:latest```
```sh
docker buildx build -t hello-go:alpine-latest-ms -f dockerfiles/Dockerfile.alpine-ms .
```

#### Single Dockerfile - based on ```wolfi-base:latest```
```sh
docker buildx build -t hello-go:wolfi-latest -f dockerfiles/Dockerfile.wolfi .
```

#### Multi-stage build based on ```wolfi-base:latest```
```sh
docker buildx build -t hello-go:wolfi-latest-ms -f dockerfiles/Dockerfile.wolfi-ms .
```

### **2. Chainguard's way to build containers using melange+apko**
#### Building ```hello-go``` from source according to ```melange.yaml```
##### Using ```melange:latest``` container:
```sh
docker run --privileged --rm -v "${PWD}":/work \
  cgr.dev/chainguard/melange:latest build melange.yaml \
  --arch amd64,aarch64 \
  --signing-key melange.rsa
```
##### or using ```melange``` directly on host:
```sh
melange build melange.yaml --arch amd64,aarch64 --signing-key melange.rsa
```

#### Assmebling the container using ```apko-dev.yaml``` and ```apko-prod.yaml```
##### Using ```apko:latest``` container:
```sh
docker run --rm --workdir /work -v ${PWD}:/work cgr.dev/chainguard/apko:latest \
  build apko-dev.yaml \
  hello-go:wolfi-latest-apko-dev \ 
  hello-go-dev.tar --arch host
```
```sh
docker run --rm --workdir /work -v ${PWD}:/work cgr.dev/chainguard/apko:latest \   
  build apko-prod.yaml \
  hello-go:wolfi-latest-apko-prod \ 
  hello-go-prod.tar --arch host
```
#### or using ```apko``` directly on host:
```sh
apko build apko-dev.yaml hello-go:wolfi-latest-apko-dev hello-go-dev.tar --arch host
```
```sh
apko build apko-prod.yaml hello-go:wolfi-latest-apko-prod hello-go-prod.tar --arch host
```

#### Loading container using ```docker load < ...```:
```sh
docker load < hello-go-dev.tar
```

```sh
docker load < hello-go-prod.tar
```

### **3. Scanning the created containers using ```grype``` or ```trivy```:**
#### Comparing vulnerabilities in Single and Multi-stage Dockerfile builds
```sh
grype <image:tag>
```
```sh
trivy image <image:tag>
```

#### Comparing vulnerabilities in melange+apko builds
##### Reviewing the SBOM (dev|prod)
```sh
cat hello-go-dev-sbom-index.spdx.json | jq .
```
```sh
cat hello-go-prod-sbom-index.spdx.json | jq .
```

### **4. Entering the built container using  ```sh```:**
#### Wolfi-based ```dev``` image:
```sh
docker run --rm -it -u root --entrypoint=sh hello-go:wolfi-latest-apko-dev-amd64 
```
#### Wolfi-based ```prod``` image:
```sh
docker run --rm -it -u root --entrypoint=sh hello-go:wolfi-latest-apko-prod-amd64
```

