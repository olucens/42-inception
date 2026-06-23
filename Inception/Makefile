COMPOSE_FILE	= srcs/docker-compose.yml
DATA_DIR		= /home/akuzmin/data

all: setup
	docker compose -f $(COMPOSE_FILE) up --build -d

# Create host data directories (named volumes need them to pre-exist)
setup:
	mkdir -p $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress

down:
	docker compose -f $(COMPOSE_FILE) down

clean: down

fclean: clean
	docker compose -f $(COMPOSE_FILE) down -v --rmi all 2>/dev/null; true
	rm -rf $(DATA_DIR)/mariadb/* $(DATA_DIR)/wordpress/*

re: fclean all

logs:
	docker compose -f $(COMPOSE_FILE) logs -f

ps:
	docker compose -f $(COMPOSE_FILE) ps

.PHONY: all setup down clean fclean re logs ps
