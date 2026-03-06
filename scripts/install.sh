#!/bin/bash
# =============================================================================
# install.sh — CC_POST_BUILD_HOOK
# Exécuté à chaque déploiement (build).
# Responsabilités :
#   - Télécharger rclone (binaire statique, mis en cache par Clever Cloud)
#   - Détecter la version actuellement installée (depuis env var NC_VERSION)
#   - Calculer le chemin de migration si nécessaire (step-by-step)
#   - Télécharger et appliquer chaque version intermédiaire dans l'ordre
#
# Variables optionnelles :
#   NEXTCLOUD_VERSION : version cible (défaut : latest stable)
#   NC_VERSION        : version actuellement installée (persistée via API CC)
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Fonctions utilitaires
# -----------------------------------------------------------------------------

major_version() { echo "$1" | cut -d. -f1; }

latest_in_major() {
    local major="$1"
    curl -s "https://download.nextcloud.com/server/releases/" \
        | grep -oP "nextcloud-${major}\.[0-9]+\.[0-9]+\.zip" \
        | grep -v "beta\|rc\|RC" \
        | sed 's/nextcloud-//;s/\.zip//' \
        | sort -t. -k1,1n -k2,2n -k3,3n \
        | tail -1
}

apply_version() {
    local version="$1"
    echo "[INFO] Application de Nextcloud $version..."
    wget -q "https://download.nextcloud.com/server/releases/nextcloud-${version}.zip" \
        -O nextcloud-dl.zip
    unzip -q nextcloud-dl.zip
    rm -rf nextcloud/config
    shopt -s dotglob
    cp -rf nextcloud/* .
    rm -rf nextcloud nextcloud-dl.zip
    echo "[OK] Nextcloud $version extrait."
}

# -----------------------------------------------------------------------------
# Téléchargement de rclone (binaire statique)
# Mis en cache par Clever Cloud dans le build cache — téléchargé une seule fois
# -----------------------------------------------------------------------------
RCLONE_BIN="$(pwd)/bin/rclone"
if [ ! -f "$RCLONE_BIN" ]; then
    echo "[INFO] Téléchargement de rclone..."
    mkdir -p "$(pwd)/bin"
    curl -fsSL "https://downloads.rclone.org/rclone-current-linux-amd64.zip" \
        -o /tmp/rclone.zip
    unzip -q /tmp/rclone.zip -d /tmp/rclone_extract
    mv /tmp/rclone_extract/rclone-*/rclone "$RCLONE_BIN"
    chmod +x "$RCLONE_BIN"
    rm -rf /tmp/rclone.zip /tmp/rclone_extract
    echo "[OK] rclone installé : $($RCLONE_BIN --version | head -1)"
else
    echo "[OK] rclone déjà en cache : $($RCLONE_BIN --version | head -1)"
fi

# -----------------------------------------------------------------------------
# Résolution de la version cible
# -----------------------------------------------------------------------------
if [ -z "$NEXTCLOUD_VERSION" ]; then
    echo "[INFO] NEXTCLOUD_VERSION non définie — récupération de la dernière version stable..."
    NC_TARGET=$(curl -s "https://api.github.com/repos/nextcloud/server/releases/latest" \
        | grep '"tag_name"' \
        | sed 's/.*"v\([^"]*\)".*/\1/')
    [ -z "$NC_TARGET" ] && NC_TARGET="33.0.0" && echo "[WARN] Fallback sur 33.0.0"
    echo "[INFO] Dernière version stable détectée : $NC_TARGET"
else
    NC_TARGET="$NEXTCLOUD_VERSION"
    echo "[INFO] Version cible épinglée : $NC_TARGET"
fi

# -----------------------------------------------------------------------------
# Détection de la version actuellement installée
# Sans FS Bucket : NC_VERSION est persistée comme env var Clever Cloud
# -----------------------------------------------------------------------------
NC_CURRENT=$(echo "${NC_VERSION:-}" | cut -d. -f1-3)

# -----------------------------------------------------------------------------
# Calcul du chemin de migration
# -----------------------------------------------------------------------------
if [ -z "$NC_CURRENT" ]; then
    echo "[INFO] Aucune installation existante détectée — installation directe de $NC_TARGET."
    apply_version "$NC_TARGET"
else
    MAJOR_CURRENT=$(major_version "$NC_CURRENT")
    MAJOR_TARGET=$(major_version "$NC_TARGET")
    echo "[INFO] Version actuelle : $NC_CURRENT (majeure : $MAJOR_CURRENT)"
    echo "[INFO] Version cible    : $NC_TARGET (majeure : $MAJOR_TARGET)"

    if [ "$MAJOR_CURRENT" -eq "$MAJOR_TARGET" ]; then
        echo "[INFO] Même version majeure — mise à jour directe."
        apply_version "$NC_TARGET"

    elif [ "$MAJOR_TARGET" -lt "$MAJOR_CURRENT" ]; then
        echo "[ERR] Downgrade interdit : $NC_CURRENT → $NC_TARGET"
        exit 1

    else
        echo "[INFO] Migration step-by-step : $NC_CURRENT → $NC_TARGET"
        STEP=$MAJOR_CURRENT
        while [ "$STEP" -lt "$MAJOR_TARGET" ]; do
            NEXT=$((STEP + 1))
            STEP_VERSION=$(latest_in_major "$NEXT")
            [ -z "$STEP_VERSION" ] && echo "[ERR] Version stable introuvable pour majeure $NEXT" && exit 1
            echo "[INFO] Étape intermédiaire : → $STEP_VERSION"
            apply_version "$STEP_VERSION"
            STEP=$NEXT
        done
        echo "[INFO] Application de la version cible finale : $NC_TARGET"
        apply_version "$NC_TARGET"
    fi
fi

echo "[OK] Nextcloud $NC_TARGET prêt pour le démarrage."

chmod +x scripts/run.sh scripts/install.sh scripts/skeleton.sh scripts/cron.sh scripts/sync-apps.sh 2>/dev/null || true
