init:
	git config --local core.hooksPath .githooks && \
	chmod -R +x .githooks/

# swiftFormatを走らせます
format: 
	cd ./BuildTools && \
	swift build && \
	swift run -c release swiftformat ../ 