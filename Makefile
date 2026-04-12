SHELL := /usr/bin/env bash

.PHONY: lint pycompile verify print-client print-policy reality-lint lint-log tests test-log ss2022-regression upgrade-xray

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

lint-log:
	@sudo /usr/local/bin/neflarectl lint-log

tests:
	@sudo /usr/local/bin/neflarectl tests

test-log:
	@sudo /usr/local/bin/neflarectl test-log

ss2022-regression:
	@sudo verify/check-ss2022-firewall.sh

upgrade-xray:
	@sudo ./install.sh --upgrade-xray
