#!/bin/bash
# =============================================================================
# run.sh — CC_PRE_RUN_HOOK
# Exécuté à CHAQUE démarrage de l'instance (premier démarrage et redémarrages).
# Responsabilités :
#   - Créer les dossiers persistants sur le FS Bucket
#   - Créer les symlinks vers le FS Bucket
#   - Détecter si c'est un premier démarrage ou un redémarrage
#   - Installer Nextcloud au premier démarrage
# =============================================================================

set -e

echo "==> Démarrage Nextcloud..."

# -----------------------------------------------------------------------------
# Vérification des variables d'environnement obligatoires
# -----------------------------------------------------------------------------
REQUIRED_VARS=(
    NEXTCLOUD_DOMAIN NEXTCLOUD_ADMIN_USER NEXTCLOUD_ADMIN_PASSWORD
    POSTGRESQL_ADDON_DB POSTGRESQL_ADDON_HOST POSTGRESQL_ADDON_PORT
    POSTGRESQL_ADDON_USER POSTGRESQL_ADDON_PASSWORD
    REDIS_HOST REDIS_PORT REDIS_PASSWORD
    CELLAR_ADDON_KEY_ID CELLAR_ADDON_KEY_SECRET CELLAR_ADDON_HOST CELLAR_BUCKET_NAME
)
MISSING=0
for VAR in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!VAR}" ]; then echo "[ERR] Variable manquante : $VAR"; MISSING=1; fi
done
[ "$MISSING" -eq 1 ] && echo "[ERR] Variables manquantes, arrêt." && exit 1
echo "[OK] Variables d'environnement OK."

# -----------------------------------------------------------------------------
# Chemins dynamiques — indépendants de l'ID de déploiement Clever Cloud
# REAL_APP : répertoire racine de l'application sur la VM
# NC_STORAGE : point de montage du FS Bucket (persistant entre redémarrages)
# -----------------------------------------------------------------------------
REAL_APP=$(cd "$(dirname "$0")/.." && pwd)
NC_STORAGE="$REAL_APP/app/storage"
echo "[INFO] REAL_APP=$REAL_APP"
echo "[INFO] NC_STORAGE=$NC_STORAGE"

# -----------------------------------------------------------------------------
# Création des dossiers persistants sur le FS Bucket
# -----------------------------------------------------------------------------
mkdir -p \
    "$NC_STORAGE/config" \
    "$NC_STORAGE/data" \
    "$NC_STORAGE/custom_apps" \
    "$NC_STORAGE/themes" \
    "$NC_STORAGE/logs"

# -----------------------------------------------------------------------------
# Symlinks : redirige les dossiers Nextcloud vers le FS Bucket persistant
# -----------------------------------------------------------------------------
rm -rf "$REAL_APP/config"      && ln -s "$NC_STORAGE/config"      "$REAL_APP/config"
rm -rf "$REAL_APP/data"        && ln -s "$NC_STORAGE/data"        "$REAL_APP/data"
rm -rf "$REAL_APP/custom_apps" && ln -s "$NC_STORAGE/custom_apps" "$REAL_APP/custom_apps"
rm -rf "$REAL_APP/themes"      && ln -s "$NC_STORAGE/themes"      "$REAL_APP/themes"
echo "[OK] Symlinks créés vers le FS Bucket."

# -----------------------------------------------------------------------------
# Copie des fichiers de config fragmentée vers config/ persistant
# -----------------------------------------------------------------------------
cp "$REAL_APP/config-git/"*.config.php "$NC_STORAGE/config/" 2>/dev/null || true

# -----------------------------------------------------------------------------
# Forcer memory_limit et opcache via .user.ini — lu par PHP-FPM
# -----------------------------------------------------------------------------
cat > "$REAL_APP/.user.ini" << 'EOF'
memory_limit = 512M
output_buffering = 0
opcache.max_accelerated_files = 20000
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 16
opcache.revalidate_freq = 60
EOF

# -----------------------------------------------------------------------------
# Détection premier démarrage vs redémarrage
# -----------------------------------------------------------------------------
if [ -f "$NC_STORAGE/config/config.php" ]; then
    # -------------------------------------------------------------------------
    # REDÉMARRAGE — instance existante détectée
    # -------------------------------------------------------------------------
    echo "[INFO] Instance existante détectée — redémarrage."

    php "$REAL_APP/occ" upgrade --no-interaction 2>/dev/null || true
    php "$REAL_APP/occ" db:add-missing-indices --no-interaction 2>/dev/null || true

else
    # -------------------------------------------------------------------------
    # PREMIER DÉMARRAGE — installation complète de Nextcloud
    # -------------------------------------------------------------------------
    echo "[INFO] Aucune instance détectée — premier démarrage."

    echo "[INFO] Attente de PostgreSQL..."
    PG_READY=0
    for i in $(seq 1 30); do
        if PGPASSWORD="$POSTGRESQL_ADDON_PASSWORD" psql \
            -h "$POSTGRESQL_ADDON_HOST" \
            -p "$POSTGRESQL_ADDON_PORT" \
            -U "$POSTGRESQL_ADDON_USER" \
            -d "$POSTGRESQL_ADDON_DB" \
            -c "SELECT 1;" >/dev/null 2>&1; then
            PG_READY=1
            echo "[OK] PostgreSQL prêt après $i tentative(s)."
            break
        fi
        sleep 3
    done
    [ "$PG_READY" = "0" ] && echo "[ERR] Timeout — PostgreSQL non disponible." && exit 1

    php "$REAL_APP/occ" maintenance:install \
        --database=pgsql \
        --database-name="$POSTGRESQL_ADDON_DB" \
        --database-host="$POSTGRESQL_ADDON_HOST:$POSTGRESQL_ADDON_PORT" \
        --database-user="$POSTGRESQL_ADDON_USER" \
        --database-pass="$POSTGRESQL_ADDON_PASSWORD" \
        --admin-user="$NEXTCLOUD_ADMIN_USER" \
        --admin-pass="$NEXTCLOUD_ADMIN_PASSWORD" \
        --data-dir="$NC_STORAGE/data" \
        --no-interaction

    php "$REAL_APP/occ" config:system:set trusted_domains 0 --value="$NEXTCLOUD_DOMAIN" --no-interaction
    php "$REAL_APP/occ" config:system:set overwrite.cli.url --value="https://$NEXTCLOUD_DOMAIN" --no-interaction
    php "$REAL_APP/occ" config:system:set overwriteprotocol --value="https" --no-interaction
    php "$REAL_APP/occ" config:system:set overwritehost --value="$NEXTCLOUD_DOMAIN" --no-interaction

    php "$REAL_APP/occ" config:system:set forwarded_for_headers 0 --value="HTTP_X_FORWARDED_FOR" --no-interaction
    php "$REAL_APP/occ" config:system:set trusted_proxies 0 --value="10.0.0.0/8" --no-interaction
    php "$REAL_APP/occ" config:system:set trusted_proxies 1 --value="172.16.0.0/12" --no-interaction
    php "$REAL_APP/occ" config:system:set trusted_proxies 2 --value="192.168.0.0/16" --no-interaction

    php "$REAL_APP/occ" config:system:set redis host --value="$REDIS_HOST" --no-interaction
    php "$REAL_APP/occ" config:system:set redis port --value="$REDIS_PORT" --no-interaction
    php "$REAL_APP/occ" config:system:set redis password --value="$REDIS_PASSWORD" --no-interaction
    php "$REAL_APP/occ" config:system:set memcache.local       --value='\OC\Memcache\Redis' --no-interaction
    php "$REAL_APP/occ" config:system:set memcache.distributed --value='\OC\Memcache\Redis' --no-interaction
    php "$REAL_APP/occ" config:system:set memcache.locking     --value='\OC\Memcache\Redis' --no-interaction

    echo "[OK] Installation Nextcloud terminée."

    php "$REAL_APP/occ" db:add-missing-indices --no-interaction 2>/dev/null || true
    php "$REAL_APP/occ" maintenance:repair --include-expensive --no-interaction 2>/dev/null || true

    echo "[OK] Objectstore S3 actif via config-git/20-objectstore.config.php"

fi

# -----------------------------------------------------------------------------
# Paramètres appliqués à chaque démarrage (idempotents)
# -----------------------------------------------------------------------------
php "$REAL_APP/occ" config:system:set maintenance_window_start --value=1 --type=integer --no-interaction 2>/dev/null || true
php "$REAL_APP/occ" config:system:set default_phone_region --value="FR" --no-interaction 2>/dev/null || true
php "$REAL_APP/occ" config:app:set core backgroundjobs_mode --value webcron --no-interaction 2>/dev/null || true

# -----------------------------------------------------------------------------
# Désactivation du mode maintenance (sécurité)
# -----------------------------------------------------------------------------
php "$REAL_APP/occ" maintenance:mode --off --no-interaction 2>/dev/null || true


# -----------------------------------------------------------------------------
# Crontab — réécriture avec le chemin réel à chaque démarrage
# -----------------------------------------------------------------------------
echo "*/5 * * * * $REAL_APP/scripts/cron.sh" | crontab -
echo "[OK] Crontab mise à jour : $REAL_APP/scripts/cron.sh"

echo "[OK] Nextcloud prêt : https://$NEXTCLOUD_DOMAIN"
