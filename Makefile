# Makefile for softandpixels
#
# Targets:
#   make up     - Build and start containers
#   make down   - Stop containers (preserve volumes)
#   make logs   - Follow container logs

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f

.PHONY: up down logs