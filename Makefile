# Copyright 2016 PreEmptive Solutions, LLC
DISTDIR=PPiOS-CG-v1.0.0
BUILDDIR=build
PROGRAM=$(BUILDDIR)/Build/Products/Release/ios-class-guard
DISTPACKAGE=$(DISTDIR).tgz

.PHONY: default
default: all

.PHONY: all
all: Pods $(PROGRAM)

.PHONY: dist
dist: $(DISTPACKAGE)

Pods Podfile.lock: Podfile
	pod install

$(PROGRAM): Pods
	xctool \
		-workspace ios-class-guard.xcworkspace \
		-scheme ios-class-guard \
		-configuration Release \
		-derivedDataPath $(BUILDDIR) \
		-reporter plain \
		-reporter junit:$(BUILDDIR)/unit-test-report.xml \
		clean build test

$(DISTPACKAGE): distclean $(PROGRAM)
	mkdir -p $(DISTDIR)
	cp $(PROGRAM) \
		README.md \
		LICENSE.txt \
		ThirdPartyLicenses.txt \
		CHANGELOG.md \
		$(DISTDIR)
	tar -cvpzf $@ --options gzip:compression-level=9 $(DISTDIR)

.PHONY: clean
clean:
	$(RM) -r build Pods

.PHONY: distclean
distclean: clean
	$(RM) -r $(DISTDIR) $(DISTPACKAGE)
