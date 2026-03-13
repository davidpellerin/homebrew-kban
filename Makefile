.PHONY: help test test-bash test-python lint install uninstall

PREFIX ?= $(HOME)/.local

help: ## Show this help message
	@echo "Usage: make <target>"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-15s %s\n", $$1, $$2}'

test: lint test-bash test-python ## Run lint and all tests

lint: ## Run shellcheck on bin/kban
	shellcheck bin/kban

test-bash: ## Run bats tests
	bats tests/kban.bats

test-python: ## Run pytest tests
	pytest tests/test_serve.py -v -p no:langsmith --cov=web --cov-report=term-missing

install: ## Install kban to PREFIX (default: $(PREFIX))
	install -Dm755 bin/kban $(PREFIX)/share/kban/bin/kban
	install -Dm644 web/serve.py $(PREFIX)/share/kban/web/serve.py
	install -Dm644 web/index.html $(PREFIX)/share/kban/web/index.html
	install -Dm644 templates/skills/kban/SKILL.md $(PREFIX)/share/kban/templates/skills/kban/SKILL.md
	install -Dm644 templates/sample-tickets/sample-ticket.md $(PREFIX)/share/kban/templates/sample-tickets/sample-ticket.md
	mkdir -p $(PREFIX)/bin
	ln -sf $(PREFIX)/share/kban/bin/kban $(PREFIX)/bin/kban
	@echo "Installed kban → $(PREFIX)/bin/kban"
	@echo "Make sure $(PREFIX)/bin is in your PATH"

uninstall: ## Remove kban from PREFIX
	rm -f $(PREFIX)/bin/kban
	rm -rf $(PREFIX)/share/kban
	@echo "Uninstalled kban from $(PREFIX)"
