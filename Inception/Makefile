# ---------------------------------------------------------------------------
# Inception - Makefile
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
# all - the one command an evaluator will type.
#
# --wait blocks until every container is healthy, so when `make` returns the site
# really answers. Without it `up -d` returns while WordPress is still installing.
# ---------------------------------------------------------------------------
all: check setup
	$(COMPOSE) up --build -d --wait
	@echo ""
	@echo "  $(NAME) is up.  https://$$(grep -m1 '^DOMAIN_NAME=' $(ENV_FILE) | cut -d= -f2)"
	@echo "  add '127.0.0.1 <that domain>' to /etc/hosts if you have not already"
	@echo ""

# ---------------------------------------------------------------------------
# init - prepare a fresh `git clone`: these files are git-ignored on purpose.
# Only creates what is missing, so it never overwrites an existing password.
# Hex passwords contain no quote or shell character that SQL or sh could misread.
# ---------------------------------------------------------------------------
init:
	@test -f $(ENV_FILE) || { cp srcs/.env.example $(ENV_FILE); echo "created $(ENV_FILE)"; }
	@mkdir -p $(SECRETS_DIR)
	@for f in db_root_password db_password; do \
		test -f $(SECRETS_DIR)/$$f.txt || { \
			openssl rand -hex 24 > $(SECRETS_DIR)/$$f.txt; \
			echo "generated $(SECRETS_DIR)/$$f.txt"; \
			test -z "$$(ls -A $(DATA_DIR)/mariadb 2>/dev/null)" || \
				echo "WARNING: $(DATA_DIR)/mariadb holds the OLD passwords - run 'make fclean'"; }; \
	done
	@test -f $(SECRETS_DIR)/credentials.txt || { \
		printf 'WP_ADMIN_PASSWORD=%s\nWP_USER_PASSWORD=%s\n' \
			"$$(openssl rand -hex 12)" "$$(openssl rand -hex 12)" > $(SECRETS_DIR)/credentials.txt; \
		echo "generated $(SECRETS_DIR)/credentials.txt"; }
	@chmod 600 $(SECRETS_DIR)/*.txt

# ---------------------------------------------------------------------------
# check - fail early with a readable message instead of a cryptic compose error.
# ---------------------------------------------------------------------------
check:
	@test -f $(ENV_FILE) || { echo "ERROR: $(ENV_FILE) is missing. Run: make init"; exit 1; }
	@for f in db_root_password db_password credentials; do \
		test -f $(SECRETS_DIR)/$$f.txt || { \
			echo "ERROR: $(SECRETS_DIR)/$$f.txt is missing. Run: make init"; exit 1; }; \
	done

# ---------------------------------------------------------------------------
# setup - create the host directories the named volumes bind to.
#
# WHY this is required: the volumes use the local driver with `type: none,
# o: bind`, which binds an EXISTING directory. Unlike a plain bind mount, Docker
# will not create it, so `up` fails with "no such file or directory" without it.
# ---------------------------------------------------------------------------
setup:
	@mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
up: check setup
	$(COMPOSE) up -d --wait

build: check
	$(COMPOSE) build

# down - stop and remove containers and the network. Volumes SURVIVE, so the site
# and the database are still there after `make down && make`.
down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

# clean - containers, network and images gone; DATA STILL THERE.
# The leading `-` lets this run on a clone without srcs/.env, where compose
# cannot load the project at all.
clean:
	-$(COMPOSE) down --rmi all

# fclean - the destructive one. -v removes the named volumes; the directories
# behind them must then be deleted separately.
#
# WHY sudo: the containers chowned those files to mysql and www-data, so the
# user running make has no right to delete them.
fclean:
	-$(COMPOSE) down --rmi all -v
	sudo rm -rf $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress

re: fclean all

# ---------------------------------------------------------------------------
# Inspection helpers - used constantly during the defence.
# ---------------------------------------------------------------------------
logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

# Prove TLS 1.2/1.3 only: tls1 and tls1_1 MUST be refused, the others accepted.
#
# WHY @SECLEVEL=0: a recent OpenSSL client may refuse to even offer TLS 1.0/1.1,
# so without it the test could prove something about the CLIENT. With it the
# client offers the old protocol and the SERVER has to reject it.
tls-test:
	@DOMAIN=$$(grep -m1 '^DOMAIN_NAME=' $(ENV_FILE) | cut -d= -f2); \
	for v in tls1 tls1_1 tls1_2 tls1_3; do \
		printf '%-8s ' "$$v"; \
		if echo | openssl s_client -connect $$DOMAIN:443 -$$v -cipher 'DEFAULT@SECLEVEL=0' >/dev/null 2>&1; \
			then echo "ACCEPTED"; else echo "refused"; fi; \
	done

.PHONY: all init check setup up build down stop start clean fclean re logs ps tls-test
