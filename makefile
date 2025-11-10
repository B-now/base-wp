## -------- CONFIG --------
NAME        ?= wp
PROJECT_DIR := ../$(NAME)

# Charger les variables depuis .env si le fichier existe
ifneq (,$(wildcard .env))
    include .env
    export
endif

# Configuration ACF - version gratuite installée par défaut
ADMIN_EMAIL ?= admin@example.com

## -------- SETUP PROJECT --------

install-wp: check-env create-bedrock copy-env update-env generate-salts install-acf start-docker configure-wp install-contact-form install-theme seed-css theme-deps configure-vite activate-theme update-themes update-translations open-phpstorm
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
	# Définir WP_HOME / WP_SITEURL pour Bedrock si absents
	@if ! grep -q '^WP_HOME=' ./$(PROJECT_DIR)/.env; then \
		echo "WP_HOME='http://localhost:8000'" >> ./$(PROJECT_DIR)/.env; \
	fi
	@if ! grep -q '^WP_SITEURL=' ./$(PROJECT_DIR)/.env; then \
		echo "WP_SITEURL='http://localhost:8000/wp'" >> ./$(PROJECT_DIR)/.env; \
	fi

generate-salts: ## Remplace directement les salts dans .env
	@echo "🔑 Génération des WordPress salts (sans fichier temporaire)…"
	@bash -c "sed -i '/# Generate your keys/,/NONCE_SALT=.*/d' $(PROJECT_DIR)/.env && \
	curl -s https://api.wordpress.org/secret-key/1.1/salt/ \
	  | sed -E \"s/define\\('([^']+)',\\s*'([^']+)'\\);/\\1='\\2'/\" \
	  >> $(PROJECT_DIR)/.env"
	@echo "✅ Salts mis à jour dans $(PROJECT_DIR)/.env"

install-acf: ## Installe ACF en mu-plugin (préfère PRO si présent)
	@echo "🔧 Installation d'ACF en mu-plugin..."
	cd $(PROJECT_DIR) && mkdir -p web/app/mu-plugins
	# Si ACF PRO est présent localement, on l'utilise
	@if [ -d ./advanced-custom-fields-pro ]; then \
		echo "💎 ACF PRO détecté → installation en mu-plugin"; \
		mkdir -p $(PROJECT_DIR)/web/app/mu-plugins/advanced-custom-fields-pro; \
		cp -r ./advanced-custom-fields-pro/* $(PROJECT_DIR)/web/app/mu-plugins/advanced-custom-fields-pro/; \
		rm -rf $(PROJECT_DIR)/web/app/plugins/advanced-custom-fields || true; \
		rm -rf $(PROJECT_DIR)/web/app/mu-plugins/advanced-custom-fields || true; \
		echo "✅ ACF PRO installé en mu-plugin"; \
	else \
		echo "⬇️  ACF PRO non trouvé → installation de la version gratuite"; \
		cd $(PROJECT_DIR) && composer config repositories.wpackagist composer https://wpackagist.org; \
		cd $(PROJECT_DIR) && composer require wpackagist-plugin/advanced-custom-fields --no-install; \
		cd $(PROJECT_DIR) && composer install --no-dev --optimize-autoloader; \
		mkdir -p $(PROJECT_DIR)/web/app/mu-plugins/advanced-custom-fields; \
		cd $(PROJECT_DIR) && cp -r web/app/plugins/advanced-custom-fields/* web/app/mu-plugins/advanced-custom-fields/; \
		cd $(PROJECT_DIR) && rm -rf web/app/plugins/advanced-custom-fields; \
		echo "✅ ACF (gratuit) installé en mu-plugin"; \
	fi

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
	cd $(PROJECT_DIR) && docker compose exec -T database mysql -uroot -ppassword -e "CREATE DATABASE IF NOT EXISTS \`$(NAME)\`;"
	@echo "✅ Base de données créée"

configure-wp: ## Configure WordPress automatiquement (sans interaction)
	@echo "🔧 Configuration automatique de WordPress..."
	@echo "📝 Titre du site: $(shell echo $(NAME) | sed 's/[-_]/ /g' | sed 's/\b\w/\U&/g')"
	@echo "⏳ Vérification que la DB répond..."
	@until cd $(PROJECT_DIR) && docker compose exec -T database mysql -uroot -ppassword -e "SELECT 1;" > /dev/null 2>&1; do \
		echo "⏳ Base de données pas encore prête, attente..."; \
		sleep 3; \
	done
	@echo "✅ DB OK"
	# Installer WP si non installé, avec quelques tentatives de retry
	@retries=0; max=20; \
	until cd $(PROJECT_DIR) && wp core is-installed --allow-root >/dev/null 2>&1 || \
		cd $(PROJECT_DIR) && wp core install --url=localhost:8000 \
		  --title="$(shell echo $(NAME) | sed 's/[-_]/ /g' | sed 's/\b\w/\U&/g')" \
		  --admin_user=bnow_admin --admin_password=admin --admin_email=$(ADMIN_EMAIL) \
		  --skip-email --allow-root; do \
		retries=$$((retries+1)); \
		if [ $$retries -ge $$max ]; then echo "❌ Échec installation WP"; exit 1; fi; \
		echo "↻ Retry installation WP ($$retries/$$max)..."; \
		sleep 3; \
	done; \
	echo "✅ WordPress installé";
	# Langue et réglages
	cd $(PROJECT_DIR) && wp language core install fr_FR --allow-root || true
	cd $(PROJECT_DIR) && (wp site switch-language fr_FR --allow-root || wp language core activate fr_FR --allow-root) || true
	cd $(PROJECT_DIR) && wp option update WPLANG fr_FR --allow-root || true
	cd $(PROJECT_DIR) && wp option update blogdescription "" --allow-root || true
	# Permaliens (avec retry silencieux)
	cd $(PROJECT_DIR) && wp rewrite structure '/%postname%/' --allow-root || echo "⚠️  Permaliens: tentative ultérieure"
	cd $(PROJECT_DIR) && wp rewrite flush --hard --allow-root || true
	@echo "✅ Permaliens configurés : /%postname%/"
	@echo "✅ WordPress configuré avec succès"
	@echo "🔑 Admin: bnow_admin / admin"

install-theme: ## Installe le thème Sage
	cd $(PROJECT_DIR) && make install-theme

seed-css: ## Copie utilities/variables/functions SCSS du squelette dans le thème
	@echo "🎨 Copie des utilitaires SCSS dans le thème..."
	@theme_dir=$(PROJECT_DIR)/web/app/themes/$(NAME); \
	mkdir -p "$$theme_dir/resources/css"; \
	: # Copier en priorité css_base si présent dans le repo racine \
	if [ -d ./css_base ]; then \
		echo "➡️  Copie de ./css_base → $$theme_dir/resources/css"; \
		cp -r ./css_base/* "$$theme_dir/resources/css/"; \
	else \
		: # Copier les répertoires dédiés s'ils existent dans le repo racine \
		if [ -d ./utilities ]; then \
			echo "➡️  Copie de ./utilities → $$theme_dir/resources/css/utilities"; \
			mkdir -p "$$theme_dir/resources/css/utilities"; \
			cp -r ./utilities/* "$$theme_dir/resources/css/utilities/"; \
		fi; \
		if [ -d ./variables ]; then \
			echo "➡️  Copie de ./variables → $$theme_dir/resources/css/variables"; \
			mkdir -p "$$theme_dir/resources/css/variables"; \
			cp -r ./variables/* "$$theme_dir/resources/css/variables/"; \
		fi; \
		if [ -d ./functions ]; then \
			echo "➡️  Copie de ./functions → $$theme_dir/resources/css/functions"; \
			mkdir -p "$$theme_dir/resources/css/functions"; \
			cp -r ./functions/* "$$theme_dir/resources/css/functions/"; \
		fi; \
	fi; \
	if [ -d ./components ]; then \
		echo "➡️  Copie de ./components → $$theme_dir/resources/css/components"; \
		mkdir -p "$$theme_dir/resources/css/components"; \
		cp -r ./components/* "$$theme_dir/resources/css/components/"; \
	fi; \
	: # Générer app.scss d'entrée avec nos imports utilitaires \
	mkdir -p "$$theme_dir/resources/css"; \
	printf '%s\n' \
	"@use 'utilities/index' as *;" \
	"@use 'utilities/reset';" \
	"@use 'utilities/base';" \
	"@use 'utilities/sanitize';" \
	"@use 'utilities/sanitize_assets';" \
	"@use 'utilities/sanitize_forms';" \
	"@use 'components/button';" \
	"@use 'components/title';" \
	"@use 'components/container';" \
	"@use 'components/text';" \
	> "$$theme_dir/resources/css/app.scss"; \
	echo "✅ Utilitaires SCSS copiés"

install-contact-form: ## Installe Contact Form 7 et Flamingo, puis active
	@echo "✉️  Installation de Contact Form 7 et Flamingo..."
	cd $(PROJECT_DIR) && composer config repositories.wpackagist composer https://wpackagist.org
	cd $(PROJECT_DIR) && composer require wpackagist-plugin/contact-form-7 wpackagist-plugin/flamingo --no-install
	cd $(PROJECT_DIR) && composer install --no-dev --optimize-autoloader
	@echo "✅ Plugins installés via Composer"
	@echo "🧩 Activation des plugins (WP-CLI)..."
	cd $(PROJECT_DIR) && wp plugin activate contact-form-7 flamingo --allow-root || true
	@echo "✅ Contact Form 7 et Flamingo activés"

theme-deps: ## Installe les dépendances Vite requises par le thème
	@echo "📦 Installation des dépendances Vite dans le thème..."
	@if [ -d $(PROJECT_DIR)/web/app/themes/$(NAME) ]; then \
		cd $(PROJECT_DIR)/web/app/themes/$(NAME) && npm i -D fast-glob vite-plugin-static-copy; \
	else \
		echo "⚠️  Dossier du thème introuvable: $(PROJECT_DIR)/web/app/themes/$(NAME)"; \
	fi

configure-vite: ## Copie et adapte le vite.config.js dans le thème
	@echo "🧩 Configuration de Vite pour le thème $(NAME)..."
	cp ./vite.config.js $(PROJECT_DIR)/web/app/themes/$(NAME)/vite.config.js
	sed -i "s|/app/themes/name/public/build/|/app/themes/$(NAME)/public/build/|g" $(PROJECT_DIR)/web/app/themes/$(NAME)/vite.config.js
	# Remplacer aussi dans la règle de proxy sans altérer la virgule/quotes
	sed -i "s|app/themes/name/public/build/|app/themes/$(NAME)/public/build/|g" $(PROJECT_DIR)/web/app/themes/$(NAME)/vite.config.js
	sed -i "s|resources/styles|resources/css|g" $(PROJECT_DIR)/web/app/themes/$(NAME)/vite.config.js
	sed -i "s|'resources/js/app.js'|'resources/js/app.ts'|g" $(PROJECT_DIR)/web/app/themes/$(NAME)/vite.config.js
	sed -i "s|'resources/js/editor.js'|'resources/js/editor.ts'|g" $(PROJECT_DIR)/web/app/themes/$(NAME)/vite.config.js
	# Mettre à jour le proxy qui exclut le dossier de build
	sed -i "s|\^/(?!app/themes/name/public/build/).*|^/(?!app/themes/$(NAME)/public/build/).*|" $(PROJECT_DIR)/web/app/themes/$(NAME)/vite.config.js
	# Basculer les entrées JS -> TS si les fichiers existent
	@if [ -f $(PROJECT_DIR)/web/app/themes/$(NAME)/resources/js/app.js ]; then \
		mv $(PROJECT_DIR)/web/app/themes/$(NAME)/resources/js/app.js $(PROJECT_DIR)/web/app/themes/$(NAME)/resources/js/app.ts; \
	fi
	@if [ -f $(PROJECT_DIR)/web/app/themes/$(NAME)/resources/js/editor.js ]; then \
		mv $(PROJECT_DIR)/web/app/themes/$(NAME)/resources/js/editor.js $(PROJECT_DIR)/web/app/themes/$(NAME)/resources/js/editor.ts; \
	fi
	# Mettre à jour les références dans les fichiers du thème
	sed -i "s/app\.js/app.ts/g" $(PROJECT_DIR)/web/app/themes/$(NAME)/vite.config.js || true
	sed -i "s/editor\.js/editor.ts/g" $(PROJECT_DIR)/web/app/themes/$(NAME)/vite.config.js || true
	sed -i "s/app\.js/app.ts/" $(PROJECT_DIR)/web/app/themes/$(NAME)/resources/views/layouts/app.blade.php || true
	sed -i "s/editor\.js/editor.ts/" $(PROJECT_DIR)/web/app/themes/$(NAME)/app/setup.php || true

activate-theme: ## Active le thème Sage
	@echo "🎨 Activation du thème Sage..."
	cd $(PROJECT_DIR) && wp theme activate $(NAME) --allow-root
	@echo "✅ Thème $(NAME) activé"

update-translations: ## Met à jour toutes les traductions (core, plugins, thèmes)
	@echo "🌐 Mise à jour des traductions (core, plugins, thèmes)..."
	cd $(PROJECT_DIR) && wp language core update --allow-root || true
	cd $(PROJECT_DIR) && wp language plugin update --all --allow-root || true
	cd $(PROJECT_DIR) && wp language theme update --all --allow-root || true
	@echo "✅ Traductions à jour"

update-themes: ## Met à jour tous les thèmes installés
	@echo "🎨 Mise à jour des thèmes..."
	cd $(PROJECT_DIR) && wp theme update --all --allow-root || true
	@echo "✅ Thèmes à jour"

make-command:
	cd $(PROJECT_DIR) && make install-theme



open-phpstorm: ## Ouvre PHPStorm dans le projet
	phpstorm $(PROJECT_DIR)