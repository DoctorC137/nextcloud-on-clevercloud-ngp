# tools/

Ce dossier contient des utilitaires de maintenance réservés au développement et aux tests.

## ⚠️ Avertissement

Les scripts dans ce dossier effectuent des opérations **destructives et irréversibles**. Ils ne sont pas destinés à un usage en production.

---

## clever-destroy.sh

Supprime **complètement et définitivement** une installation Nextcloud sur Clever Cloud :

- L'application PHP et tous ses addons
- La base de données PostgreSQL et **toutes ses données**
- Le FS Bucket et toute la configuration persistante
- Le bucket Cellar S3 et **tous les fichiers uploadés par les utilisateurs**
- Le remote git `clever` et le fichier `.clever.json` local

**Aucune récupération possible après confirmation.**

### Usage

```bash
bash tools/clever-destroy.sh <app-name> [org-id]

# Exemple
bash tools/clever-destroy.sh nextcloud orga_xxx
```

Le script demande de taper `supprimer` pour confirmer — une faute de frappe annule sans rien supprimer.

### Cas d'usage typique

Destroy + redéploiement propre pendant le développement :

```bash
bash tools/clever-destroy.sh nextcloud orga_xxx
bash deploy/clever-deploy.sh
```
