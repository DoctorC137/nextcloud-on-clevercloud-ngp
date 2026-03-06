<?php
// =============================================================================
// config-git/20-objectstore.config.php
// Configuration du stockage objet S3 (Cellar) pour Nextcloud.
// Chargé automatiquement par Nextcloud depuis config/ via symlink run.sh.
// Les valeurs sensibles sont lues depuis les variables d'environnement Clever Cloud.
// =============================================================================

$CONFIG = array(

  'objectstore' => array(
    'class'     => 'OC\Files\ObjectStore\S3',
    'arguments' => array(
      'bucket'         => getenv('CELLAR_BUCKET_NAME'),
      'autocreate'     => true,
      'key'            => getenv('CELLAR_ADDON_KEY_ID'),
      'secret'         => getenv('CELLAR_ADDON_KEY_SECRET'),
      'hostname'       => getenv('CELLAR_ADDON_HOST'),
      'port'           => 443,
      'use_ssl'        => true,
      'region'         => 'us-east-1',
      'use_path_style' => true,
    ),
  ),

);
