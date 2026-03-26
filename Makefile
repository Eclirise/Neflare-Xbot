SHELL := /usr/bin/env bash

.PHONY: lint pycompile verify print-client print-policy reality-lint upgrade-xray

lint:
	@for file in $$(find . -type f -name '*.sh'); do bash -n "$$file"; done

pycompile:
	@python -m py_compile $$(find . -type f -name '*.py')

verify:
	@sudo ./install.sh --verify-only

print-client:
	@sudo /usr/local/bin/neflarectl print-client

print-policy:
	@sudo /usr/local/bin/neflarectl print-policy

reality-lint:
	@sudo /usr/local/bin/neflarectl reality-lint

upgrade-xray:
	@sudo ./install.sh --upgrade-xray
