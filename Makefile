# VARIANT is "base" (no NVIDIA, the default), "nvidia-open" or "nvidia-legacy".
VARIANT ?= base

.PHONY: build build-base build-nvidia-open build-nvidia-legacy build-all
build:
	bash scripts/build.sh $(VARIANT)

build-base:
	bash scripts/build.sh base

build-nvidia-open:
	bash scripts/build.sh nvidia-open

build-nvidia-legacy:
	bash scripts/build.sh nvidia-legacy

build-all: build-base build-nvidia-open build-nvidia-legacy
