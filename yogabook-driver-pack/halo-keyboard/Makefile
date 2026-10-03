PACKAGE_VERSION := $(shell dpkg-parsechangelog -S Version | sed 's/-[^-]*$$//')
ORIG_TARBALL := ../halo-keyboard_$(PACKAGE_VERSION).orig.tar.xz

.PHONY: all build clean configure deb source test

all: build

configure:
	cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTING=ON

build: configure
	cmake --build build --parallel

test: build
	ctest --test-dir build --output-on-failure

deb:
	dpkg-buildpackage --build=binary --no-sign

source:
	git archive --format=tar --prefix=halo-keyboard-$(PACKAGE_VERSION)/ HEAD -- . ':(exclude)debian' | xz -T0 > $(ORIG_TARBALL)
	dpkg-buildpackage --build=source --no-sign --no-check-builddeps

clean:
	rm -rf build
	dh clean
