<?php
// =============================================================================
// config-git/10-clevercloud.config.php
// Configuration Nextcloud spécifique à Clever Cloud.
// Ce fichier est chargé automatiquement par Nextcloud depuis config/
// Il ne contient PAS l'objectstore (injecté par run.sh après installation).
// Toutes les valeurs sensibles sont lues depuis les variables d'environnement.
// =============================================================================

$CONFIG = array(

  // ---------------------------------------------------------------------------
  // Réseau & proxy
  // Clever Cloud utilise des reverse proxies — nécessaire pour HTTPS correct
  // ---------------------------------------------------------------------------
  'overwriteprotocol' => 'https',
  'overwrite.cli.url' => 'https://' . getenv('NEXTCLOUD_DOMAIN'),
  'trusted_domains'   => array(
    0 => getenv('NEXTCLOUD_DOMAIN'),
  ),
  'trusted_proxies'   => ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'],

  // ---------------------------------------------------------------------------
  // Base de données PostgreSQL
  // Variables injectées automatiquement par l'addon Clever Cloud
  // ---------------------------------------------------------------------------
  'dbtype'     => 'pgsql',
  'dbname'     => getenv('POSTGRESQL_ADDON_DB'),
  'dbhost'     => getenv('POSTGRESQL_ADDON_HOST') . ':' . getenv('POSTGRESQL_ADDON_PORT'),
  'dbuser'     => getenv('POSTGRESQL_ADDON_USER'),
  'dbpassword' => getenv('POSTGRESQL_ADDON_PASSWORD'),

  // ---------------------------------------------------------------------------
  // Cache Redis — mémoire distribuée, sessions, verrouillage fichiers
  // Améliore significativement les performances
  // ---------------------------------------------------------------------------
  'memcache.local'       => '\OC\Memcache\Redis',
  'memcache.distributed' => '\OC\Memcache\Redis',
  'memcache.locking'     => '\OC\Memcache\Redis',
  'redis' => array(
    'host'     => getenv('REDIS_HOST'),
    'port'     => (int) getenv('REDIS_PORT'),
    'password' => getenv('REDIS_PASSWORD'),
  ),

);
