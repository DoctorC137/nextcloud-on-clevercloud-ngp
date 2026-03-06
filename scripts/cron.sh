#!/bin/bash -l
# =============================================================================
# cron.sh — Cron Nextcloud pour Clever Cloud
# Appelé via clevercloud/cron.json toutes les 5 minutes.
# Le -l dans le shebang est obligatoire pour accéder aux variables d'env.
# $ROOT est remplacé par Clever Cloud par le chemin réel de l'application.
# =============================================================================

REAL_APP=$(ls -d /home/bas/app_*/ 2>/dev/null | head -1 | sed 's|/$||')
[ -z "$REAL_APP" ] && exit 1

php "$REAL_APP/cron.php" >> "$REAL_APP/app/storage/logs/cron.log" 2>&1
