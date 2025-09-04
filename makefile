## -------- CONFIG --------
NAME        ?= wp
PROJECT_DIR := ../$(NAME)

## -------- SETUP PROJECT --------

install-wp: create-bedrock copy-env update-env generate-salts make-command open-phpstorm
	@echo "🎉 Projet $(NAME) prêt !"

create-bedrock: ## Crée le projet Bedrock
	composer create-project roots/bedrock $(PROJECT_DIR)

copy-env: ## Copie les fichiers nécessaires
	cp ./makefileWp ./$(PROJECT_DIR)/makefile
	cp ./docker-compose.yaml ./$(PROJECT_DIR)/docker-compose.yaml
	cp ./$(PROJECT_DIR)/.env.example ./$(PROJECT_DIR)/.env

update-env: ## Met à jour le fichier .env et docker-compose.yaml
	sed -i 's/bdd/$(NAME)/' ./$(PROJECT_DIR)/docker-compose.yaml
	sed -i 's/database_name/$(NAME)/' ./$(PROJECT_DIR)/.env
	sed -i 's/database_user/root/' ./$(PROJECT_DIR)/.env
	sed -i 's/database_password/password/' ./$(PROJECT_DIR)/.env
	sed -i "s/# DB_HOST='localhost'/DB_HOST='127.0.0.1:3306'/" ./$(PROJECT_DIR)/.env
	sed -i 's/example.com/localhost:8000/' ./$(PROJECT_DIR)/.env
	sed -i 's/isName/$(NAME)/' ./$(PROJECT_DIR)/makefile

generate-salts: ## Remplace directement les salts dans .env
	@echo "🔑 Génération des WordPress salts (sans fichier temporaire)…"
	@bash -c "sed -i '/# Generate your keys/,/NONCE_SALT=.*/d' $(PROJECT_DIR)/.env && \
	curl -s https://api.wordpress.org/secret-key/1.1/salt/ \
	  | sed -E \"s/define\\('([^']+)',\\s*'([^']+)'\\);/\\1='\\2'/\" \
	  >> $(PROJECT_DIR)/.env"
	@echo "✅ Salts mis à jour dans $(PROJECT_DIR)/.env"

make-command:
	cd $(PROJECT_DIR) && make install-theme

open-phpstorm: ## Ouvre PHPStorm dans le projet
	phpstorm $(PROJECT_DIR)