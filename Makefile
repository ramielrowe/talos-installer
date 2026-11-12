# VARIANT is "current" (modern NVIDIA drivers, the default) or "legacy" (Maxwell/Pascal/Volta).
VARIANT ?= current

.PHONY: build build-current build-legacy build-all
build:
	bash scripts/build.sh $(VARIANT)

build-current:
	bash scripts/build.sh current

build-legacy:
	bash scripts/build.sh legacy

build-all: build-current build-legacy
