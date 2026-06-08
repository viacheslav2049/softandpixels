# Makefile for softandpixels
#
# Targets:
#   make up     - Build and start containers
#   make down   - Stop containers (preserve volumes)
#   make logs   - Follow container logs
#   make trust  - Trust the dev CA certificate (macOS/Linux)

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f

trust:
	@echo "Extracting certificate from proxy container..."
	@docker compose cp proxy:/data/caddy/pki/authorities/local/root.crt ./dev-ca.crt 2>/dev/null || (echo "Error: Could not extract certificate. Is the proxy container running?" && exit 1)
	@echo "Adding certificate to system trust store..."
	@bash -c 'if [ "$$(uname)" = "Darwin" ]; then \
		sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./dev-ca.crt; \
		if [ $$? -eq 0 ]; then \
			echo "Successfully added certificate to macOS keychain"; \
			rm -f ./dev-ca.crt; \
		else \
			echo "Failed to add certificate to keychain"; \
			rm -f ./dev-ca.crt; \
			exit 1; \
		fi; \
	elif [ "$$EUID" -eq 0 ] || [ "$$USER" = "root" ]; then \
		cp ./dev-ca.crt /usr/local/share/ca-certificates/caddy-dev.crt; \
		update-ca-certificates; \
		if [ $$? -eq 0 ]; then \
			echo "Successfully updated Linux CA certificates"; \
			rm -f ./dev-ca.crt; \
		else \
			echo "Failed to update CA certificates"; \
			rm -f ./dev-ca.crt; \
			exit 1; \
		fi; \
	else \
		echo "Error: Certificate installation requires admin privileges. Please run with sudo."; \
		rm -f ./dev-ca.crt; \
		exit 1; \
	fi'

.PHONY: up down logs trust