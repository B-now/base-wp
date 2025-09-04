## -------- CONFIG --------
NAME        ?= wp
PROJECT_DIR := ../$(NAME)

# Charger les variables depuis .env si le fichier existe
ifneq (,$(wildcard .env))
    include .env
    export
endif

# Configuration ACF - version gratuite installée par défaut
ADMIN_EMAIL ?= admin@localhost

## -------- SETUP PROJECT --------

install-wp: check-env create-bedrock copy-env update-env generate-salts install-acf start-docker configure-wp install-theme install-linters activate-theme open-phpstorm
	@echo "🎉 Projet $(NAME) prêt !"

check-env: ## Vérifie et crée le fichier .env si nécessaire
	@if [ ! -f .env ]; then \
		echo "📝 Création du fichier .env..."; \
		cp env.example .env; \
		echo "⚠️  Veuillez configurer votre clé ACF dans le fichier .env"; \
		echo "   Éditez le fichier .env et remplacez 'your-acf-license-key-here' par votre vraie clé"; \
	fi

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

install-acf: ## Installe ACF (version gratuite) en mu-plugin
	@echo "🔧 Installation d'ACF (version gratuite) en mu-plugin..."
	cd $(PROJECT_DIR) && composer config repositories.wpackagist composer https://wpackagist.org
	cd $(PROJECT_DIR) && composer require wpackagist-plugin/advanced-custom-fields --no-install
	cd $(PROJECT_DIR) && composer install --no-dev --optimize-autoloader
	@echo "✅ ACF (gratuit) installé avec succès"
	@echo "🔧 Configuration mu-plugin automatique..."
	cd $(PROJECT_DIR) && mkdir -p web/app/mu-plugins
	cd $(PROJECT_DIR) && mkdir -p web/app/mu-plugins/advanced-custom-fields

	cd $(PROJECT_DIR) && cp -r web/app/plugins/advanced-custom-fields/* web/app/mu-plugins/advanced-custom-fields/
	cd $(PROJECT_DIR) && rm -rf web/app/plugins/advanced-custom-fields
	@echo "✅ ACF configuré en mu-plugin"

install-linters: ## Installe les linters et outils de qualité
	@echo "🔍 Installation des linters..."
	cd $(PROJECT_DIR) && composer require --dev squizlabs/php_codesniffer wp-coding-standards/wpcs
	cd $(PROJECT_DIR)/web/app/themes/$(NAME) && npm install --save-dev stylelint stylelint-config-standard-scss eslint @wordpress/eslint-plugin @typescript-eslint/parser @typescript-eslint/eslint-plugin prettier eslint-config-prettier eslint-plugin-prettier
	@echo "✅ Linters installés"

start-docker: ## Démarre Docker et attend que la base soit prête
	@echo "🐳 Démarrage de Docker..."
	cd $(PROJECT_DIR) && docker compose up -d
	@echo "⏳ Attente que la base de données soit prête..."
	@sleep 15
	@echo "🔍 Vérification de la base de données..."
	@until cd $(PROJECT_DIR) && docker compose exec -T database mysql -uroot -ppassword -e "SELECT 1;" > /dev/null 2>&1; do \
		echo "⏳ Base de données pas encore prête, attente..."; \
		sleep 5; \
	done
	@echo "✅ Docker démarré et base de données prête"
	@echo "🗄️  Création de la base de données..."
	cd $(PROJECT_DIR) && docker compose exec -T database mysql -uroot -ppassword -e "CREATE DATABASE IF NOT EXISTS $(NAME);"
	@echo "✅ Base de données créée"

configure-wp: ## Configure WordPress automatiquement
	@echo "🔧 Configuration automatique de WordPress..."
	@echo "📝 Titre du site: $(shell echo $(NAME) | sed 's/[-_]/ /g' | sed 's/\b\w/\U&/g')"
	cd $(PROJECT_DIR) && wp core install --url=localhost:8000 --title="$(shell echo $(NAME) | sed 's/[-_]/ /g' | sed 's/\b\w/\U&/g')" --admin_user=bnow_admin --admin_password=admin --admin_email=$(ADMIN_EMAIL) --skip-email --allow-root || echo "WordPress déjà installé"
	cd $(PROJECT_DIR) && wp language core install fr_FR --allow-root
	cd $(PROJECT_DIR) && wp language core activate fr_FR --allow-root
	cd $(PROJECT_DIR) && wp option update blogdescription "" --allow-root
	cd $(PROJECT_DIR) && wp rewrite structure '/%postname%/' --allow-root || echo "⚠️  Erreur lors de la configuration des permaliens"
	@echo "✅ Permaliens configurés : /%postname%/"
	@echo "🔍 Vérification finale de la base de données..."
	@until cd $(PROJECT_DIR) && docker compose exec -T database mysql -uroot -ppassword -e "SELECT 1;" > /dev/null 2>&1; do \
		echo "⏳ Base de données pas accessible, attente..."; \
		sleep 3; \
	done
	@echo "✅ WordPress configuré avec succès"
	@echo "🔑 Admin: bnow_admin / admin"

install-theme: ## Installe le thème Sage
	cd $(PROJECT_DIR) && make install-theme

activate-theme: ## Active le thème Sage
	@echo "🎨 Activation du thème Sage..."
	cd $(PROJECT_DIR) && wp theme activate $(NAME) --allow-root
	@echo "✅ Thème $(NAME) activé"

make-command:
	cd $(PROJECT_DIR) && make install-theme



open-phpstorm: ## Ouvre PHPStorm dans le projet
	phpstorm $(PROJECT_DIR)