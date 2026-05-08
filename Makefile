.PHONY: help status push sync

.DEFAULT_GOAL := help

# --- Configuration ---
SUBDIRS := $(wildcard */Makefile)
SUBDIR_NAMES := $(patsubst %/Makefile,%,$(SUBDIRS))

# --- Help ---
help:  ## Show available targets
	@echo "Global targets:"
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
	@echo ""
	@echo "Sub-module targets (format: <dir>_<target>):"
	@for dir in $(SUBDIR_NAMES); do \
		echo "  [$$dir]"; \
		grep -E '^[a-zA-Z_-]+:.*?##' $$dir/Makefile | \
		  awk -v d=$$dir 'BEGIN {FS = ":.*?## "}; {printf "    %-20s %s\n", d"_"$$1, $$2}'; \
	done

# --- Global targets ---
status: ## Git status --short
	@git status --short

push:  ## Push current branch to all remotes using xargs
	@git remote | xargs -I {} git push {} $$(git branch --show-current)

sync: ## Add all, commit and push (usage: make sync -m "message")
	@git add .
	@git commit -m "$(if $(filter-out sync -m,$(MAKECMDGOALS)),$(filter-out sync -m,$(MAKECMDGOALS)),sync: auto-commit from Makefile)"
	@$(MAKE) push

# Support for -m flag and positional arguments
-m:
	@:
%:
	@:

# --- Dynamic targets for sub-modules ---
# Usage: make vm_debian_install
$(foreach dir,$(SUBDIR_NAMES),$(eval \
    $(dir)_%: ; @$(MAKE) -C $(dir) $* \
))
