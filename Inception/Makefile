# ---------------------------------------------------------------------------
# Inception — Makefile
#
# Subject: "A Makefile is also required and must be located at the root of your
# directory. It must set up your entire application (i.e., it has to build the
# Docker images using docker-compose.yml)."
# ---------------------------------------------------------------------------

NAME        := inception
COMPOSE     := docker compose -f srcs/docker-compose.yml
LOGIN       := akuzmin
DATA_DIR    := /home/$(LOGIN)/data
ENV_FILE    := srcs/.env
SECRETS_DIR := secrets

# .DEFAULT_GOAL makes a bare `make` run `all` even if another target is first.
.DEFAULT_GOAL := all

# ---------------------------------------------------------------------------
# all — the one command an evaluator will type.
# ---------------------------------------------------------------------------
all: check setup
	$(COMPOSE) up --build -d
	@echo ""
	@echo "  $(NAME) is up.  https://$$(grep -m1 '^DOMAIN_NAME=' $(ENV_FILE) | cut -d= -f2)"
	@echo "  add '127.0.0.1 <that domain>' to /etc/hosts if you have not already"
	@echo ""

# ---------------------------------------------------------------------------
# check — fail early with a readable message instead of a cryptic compose error.
# These files are git-ignored on purpose, so they are missing on a fresh clone.
# ---------------------------------------------------------------------------
check:
	@test -f $(ENV_FILE) || { \
		echo "ERROR: $(ENV_FILE) is missing."; \
		echo "       cp srcs/.env.example $(ENV_FILE) and edit it."; exit 1; }
	@for f in db_root_password db_password credentials; do \
		test -f $(SECRETS_DIR)/$$f.txt || { \
			echo "ERROR: $(SECRETS_DIR)/$$f.txt is missing."; \
			echo "       see DEV_DOC.md, section 'Secrets'."; exit 1; }; \
	done

# ---------------------------------------------------------------------------
# setup — create the host directories the named volumes bind to.
#
# WHY this is required: the volumes use the local driver with `type: none,
# o: bind`, which binds an EXISTING directory. Unlike a plain bind mount,
# Docker will not create it, so `up` fails with "no such file or directory"
# unless this ran first.
# ---------------------------------------------------------------------------
setup:
	@mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
up:
	$(COMPOSE) up -d

build:
	$(COMPOSE) build

# down — stop and remove containers and the network. Volumes SURVIVE, so the
# site and the database are still there after `make down && make up`. That is
# the whole point of persistent storage, and it is worth demonstrating.
down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

# clean — containers, network and images gone; DATA STILL THERE.
clean: down
	$(COMPOSE) down --rmi local 2>/dev/null || true

# fclean — the destructive one. -v removes the named volumes, and since they
# bind to $(DATA_DIR), the contents there go too. This is what you run to prove
# a from-scratch build works.
fclean: clean
	$(COMPOSE) down -v 2>/dev/null || true
	@rm -rf $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress

re: fclean all

# ---------------------------------------------------------------------------
# Inspection helpers — used constantly during the defence.
# ---------------------------------------------------------------------------
logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

# Prove TLS 1.2/1.3 only. tls1_1 MUST fail, tls1_2 and tls1_3 MUST succeed.
tls-test:
	@DOMAIN=$$(grep -m1 '^DOMAIN_NAME=' $(ENV_FILE) | cut -d= -f2); \
	for v in tls1_1 tls1_2 tls1_3; do \
		printf '%-8s ' "$$v"; \
		if echo | openssl s_client -connect $$DOMAIN:443 -$$v >/dev/null 2>&1; \
			then echo "ACCEPTED"; else echo "refused"; fi; \
	done

.PHONY: all check setup up build down stop start clean fclean re logs ps tls-test
