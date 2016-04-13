# Copyright 2016 PreEmptive Solutions LLC
buildDir=build
targetApp="$$(ls -td $$(find "$(buildDir)" -name "*.app") | head -1)"
targetAppName="$$(echo "$(targetApp)" | sed 's,.*/\([^/]*\)\.app,\1,')"
program="$$(ls -td $$(find "$(targetApp)" -type f -and -name "$(targetAppName)") | head -1)"

.PHONY: default
default:
	@echo "Usage: make <build|show|clean>"
	@echo ""
	@echo "  buildDir=$(buildDir)"
	@echo "  targetApp=$(targetApp)"
	@echo "  targetAppName=$(targetAppName)"
	@echo "  program=$(program)"
	@echo ""
	@exit 1

.PHONY: build
build:
	xcodebuild \
		-project BoxSim.xcodeproj \
		-scheme BoxSim \
		-configuration Release \
		-derivedDataPath $(buildDir) \
		clean build

.PHONY: show
show:
	otool -o -v "$(program)" | grep 'imp 0x' | grep '\[' | awk '{print $$3 " " $$4}' | sort | uniq
#	nm "$(program)"

.PHONY: clean
clean:
	$(RM) -r $(buildDir) symbols*.h symbols*.map excludes-*.list
