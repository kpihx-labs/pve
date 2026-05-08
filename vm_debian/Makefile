.PHONY: help install purge

.DEFAULT_GOAL := help

help:  ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

install:  ## Install the Debian VM on PVE host
	@bash scripts/install.sh

purge:  ## Purge the Debian VM from PVE host
	@bash scripts/purge.sh
