.PHONY: help ls setup sync-standards check-standards update-standards setup-agents

help: ## Show this help message
	@echo "Standards Repository Management"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

ls: ## List all available make targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sed 's/:.*//' | sort

setup: ## Run setup script to configure standards in a project
	@./scripts/setup.sh

sync-standards: ## Sync standards files and update .cursorrules
	@./scripts/sync-standards.sh

check-standards: ## Check if standards are up to date
	@if [ -d ".standards" ]; then \
		cd .standards && \
		git fetch origin >/dev/null 2>&1 && \
		LOCAL=$$(git rev-parse HEAD) && \
		REMOTE=$$(git rev-parse origin/main 2>/dev/null || git rev-parse origin/master 2>/dev/null) && \
		if [ "$$LOCAL" != "$$REMOTE" ] && [ -n "$$REMOTE" ]; then \
			echo "⚠️  Standards are out of date. Run 'make sync-standards'"; \
			exit 1; \
		else \
			echo "✅ Standards are up to date"; \
		fi; \
	else \
		echo "ℹ️  Not a project with standards submodule"; \
	fi

update-standards: ## Update standards submodule to latest
	@if [ -d ".standards" ]; then \
		cd .standards && \
		git pull origin main 2>/dev/null || git pull origin master 2>/dev/null && \
		cd .. && \
		cp .standards/.cursorrules .cursorrules 2>/dev/null || true && \
		echo "✅ Standards updated"; \
	else \
		echo "❌ No .standards directory found"; \
		exit 1; \
	fi

lint: ## Lint all markdown files
	@command -v markdownlint >/dev/null 2>&1 && \
		markdownlint *.md || \
		echo "ℹ️  markdownlint not installed, skipping"

format: ## Format all markdown files (if formatter available)
	@command -v prettier >/dev/null 2>&1 && \
		prettier --write "*.md" || \
		echo "ℹ️  prettier not installed, skipping"

test-scripts: ## Test setup and sync scripts
	@echo "Testing setup.sh..."
	@bash -n scripts/setup.sh && echo "✅ setup.sh syntax valid"
	@echo "Testing sync-standards.sh..."
	@bash -n scripts/sync-standards.sh && echo "✅ sync-standards.sh syntax valid"

setup-agents: ## Setup AI agent configurations (Copilot, Aider, Codex)
	@if [ -d ".standards" ]; then \
		./.standards/scripts/setup.sh; \
	elif [ -f "scripts/setup.sh" ]; then \
		./scripts/setup.sh; \
	else \
		echo "❌ Standards directory not found. Run install script first."; \
		exit 1; \
	fi

