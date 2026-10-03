PACKAGE_VERSION := $(shell dpkg-parsechangelog -S Version)
PACKAGE_ARTIFACT := artifacts/yogabook-camera_$(PACKAGE_VERSION)_all.deb

.PHONY: clean package test

test:
	bash tests/check-project.sh

package: test
	dpkg-buildpackage --build=binary --no-sign
	install -D -m 0644 ../yogabook-camera_$(PACKAGE_VERSION)_all.deb $(PACKAGE_ARTIFACT)
	dpkg-deb --info $(PACKAGE_ARTIFACT) >/dev/null
	bash tests/check-package.sh $(PACKAGE_ARTIFACT)

clean:
	$(RM) -r artifacts
