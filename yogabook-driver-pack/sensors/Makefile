PACKAGE_VERSION := $(shell dpkg-parsechangelog -S Version | sed 's/-[^-]*$$//')
ORIG_TARBALL := ../yogabook-sensors_$(PACKAGE_VERSION).orig.tar.xz

.PHONY: clean deb source test

test:
	bash tests/check-sensors.sh
	bash tests/check-thermald.sh

deb: test
	dpkg-buildpackage --build=binary --no-sign

source:
	git archive --format=tar --prefix=yogabook-sensors-$(PACKAGE_VERSION)/ HEAD -- . ':(exclude)debian' | xz -T0 > $(ORIG_TARBALL)
	dpkg-buildpackage --build=source --no-sign --no-check-builddeps

clean:
	@:
