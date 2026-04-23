<?php

/**
 * The settings file contains all of the basic settings that need to be present when a database/cache is not available.
 *
 * Simple Machines Forum (SMF)
 *
 * @author Simple Machines https://www.simplemachines.org
 * @copyright 2025 Simple Machines and individual contributors
 * @license https://www.simplemachines.org/about/smf/license.php BSD
 *
 * @version 2.1.6
 */

//######### Maintenance ##########
/**
 * The maintenance "mode"
 * Set to 1 to enable Maintenance Mode, 2 to make the forum untouchable. (you'll have to make it 0 again manually!)
 * 0 is default and disables maintenance mode.
 *
 * @var int 0, 1, 2
 * @global int $maintenance
 */
$maintenance = getenv('MAINTENANCE_MODE') !== false ? (int) getenv('MAINTENANCE_MODE') : 0;
/**
 * Title for the Maintenance Mode message.
 *
 * @var string
 * @global int $mtitle
 */
$mtitle = getenv('MAINTENANCE_TITLE') ?: "We're Working On It...";
/**
 * Description of why the forum is in maintenance mode.
 *
 * @var string
 * @global string $mmessage
 */
$mmessage = getenv('MAINTENANCE_MESSAGE')
    ?: "Okay faithful users... we're doing a little work, but news will be posted once we're back!";

//######### Forum Info ##########
/**
 * The name of your forum.
 *
 * @var string
 */
$mbname = getenv('SITE_NAME') ?: 'Wetfish Online';
/**
 * The default language file set for the forum.
 *
 * @var string
 */
$language = getenv('SITE_LANGUAGE') ?: 'english';
/**
 * URL to your forum's folder. (without the trailing /!).
 *
 * @var string
 */
$boardurl = getenv('SITE_BOARDURL') ?: 'http://127.0.0.1:8080';
/**
 * Email address to send emails from. (like noreply@yourdomain.com.).
 *
 * @var string
 */
$webmaster_email = getenv('OUTGOING_EMAIL') ?: 'noreply@wetfishonline.com';
/**
 * Name of the cookie to set for authentication.
 *
 * @var string
 */
$cookiename = getenv('SITE_COOKIE_NAME') ?: 'SMFLOCAL8080';

//######### Database Info ##########
/**
 * The database type
 * Default options: mysql, postgresql.
 *
 * @var string
 */
$db_type = 'mysql';
/**
 * The database port
 * 0 to use default port for the database type.
 *
 * @var int
 */
$db_port = getenv('DB_PORT') !== false
    ? (int) getenv('DB_PORT')
    : 0;
/**
 * The server to connect to (or a Unix socket).
 *
 * @var string
 */
$db_server = getenv('DB_HOST') ?: 'online-db-runtime';
/**
 * The database name.
 *
 * @var string
 */
$db_name = getenv('DB_NAME') ?: 'smf';
/**
 * Database username.
 *
 * @var string
 */
$db_user = getenv('DB_USERNAME') ?: '';
/**
 * Database password.
 *
 * @var string
 */
$db_passwd = getenv('DB_PASSWORD') ?: '';
/**
 * Database user for when connecting with SSI.
 *
 * @var string
 */
$ssi_db_user = getenv('SMF_SSI_USERNAME') ?: '';
/**
 * Database password for when connecting with SSI.
 *
 * @var string
 */
$ssi_db_passwd = getenv('SMF_SSI_PASSWORD') ?: '';
/**
 * A prefix to put in front of your table names.
 * This helps to prevent conflicts.
 *
 * @var string
 */
$db_prefix = getenv('SMF_DB_PREFIX') ?: 'smf_';
/**
 * Use a persistent database connection.
 *
 * @var bool
 */
$db_persist = getenv('SMF_DB_PERSIST') !== false
    ? (bool) getenv('SMF_DB_PERSIST')
    : false;

/**
 * Send emails on database connection error.
 *
 * @var bool
 */
$db_error_send = getenv('SMF_DB_ERROR_SEND') !== false
    ? (bool) getenv('SMF_DB_ERROR_SEND')
    : false;
/**
 * Override the default behavior of the database layer for mb4 handling
 * null keep the default behavior untouched.
 *
 * @var null|bool
 */
$db_mb4 = true;

//######### Cache Info ##########
/**
 * Select a cache system. You want to leave this up to the cache area of the admin panel for
 * proper detection of apc, memcached, output_cache, smf, or xcache
 * (you can add more with a mod).
 *
 * @var string
 */
$cache_accelerator = getenv('SMF_CACHE_ACCELERATOR') ?: '';
/**
 * The level at which you would like to cache. Between 0 (off) through 3 (cache a lot).
 *
 * @var int
 */
$cache_enable = getenv('SMF_CACHE_ENABLE') !== false
    ? (int) getenv('SMF_CACHE_ENABLE')
    : 0;
/**
 * This is only used for memcache / memcached. Should be a string of 'server:port,server:port'.
 *
 * @var array
 */
$cache_memcached = getenv('SMF_CACHE_MEMCACHED') ?: '';
/**
 * This is only for the 'smf' file cache system. It is the path to the cache directory.
 * It is also recommended that you place this in /tmp/ if you are going to use this.
 *
 * @var string
 */
$cachedir = getenv('SMF_CACHE_DIR') ?: dirname(__FILE__).'/cache';

//######### Image Proxy ##########
// This is done entirely in Settings.php to avoid loading the DB while serving the images
/**
 * Whether the proxy is enabled or not.
 *
 * @var bool
 */
$image_proxy_enabled = getenv('SMF_IMAGE_PROXY_ENABLED') !== false
    ? (bool) getenv('SMF_IMAGE_PROXY_ENABLED')
    : true;
/**
 * Secret key to be used by the proxy.
 *
 * @var string
 */
$image_proxy_secret = getenv('SMF_IMAGE_PROXY_SECRET') ?: 'smfisawesome';
/**
 * Maximum file size (in KB) for individual files.
 *
 * @var int
 */
$image_proxy_maxsize = getenv('SMF_IMAGE_PROXY_MAXSIZE') !== false
    ? (int) getenv('SMF_IMAGE_PROXY_MAXSIZE')
    : 5192;

//######### Directories/Files ##########
// Note: These directories do not have to be changed unless you move things.
/**
 * The absolute path to the forum's folder. (not just '.'!).
 *
 * @var string
 */
$boarddir = getenv('SMF_BOARD_DIR') ?: dirname(__FILE__);
/**
 * Path to the Sources directory.
 *
 * @var string
 */
$sourcedir = getenv('SMF_SOURCE_DIR') ?: $boarddir.'/Sources';
/**
 * Path to the Packages directory.
 *
 * @var string
 */
$packagesdir = getenv('SMF_PACKAGES_DIR') ?: $boarddir.'/Packages';
/**
 * Path to the tasks directory.
 *
 * @var string
 */
$tasksdir = getenv('SMF_TASKS_DIR') ?: $sourcedir.'/tasks';
/**
 * Path to the Packages directory.
 *
 * @var string
 */
$scripturl = getenv('SMF_SCRIPT_URL') ?: $boardurl.'/index.php';
/**
 * URL to the Packages directory.
 *
 * @var string
 */
$packagesurl = getenv('SMF_PACKAGES_URL') ?: $boardurl.'/Packages';
/**
 * The auth secret to be used across requests. If this isn't in the env,
 * SMF will cryptographically generate a value and WRITE IT TO SETTINGS.PHP (BAD)
 * Changing this will cause all auth tokens to invalidate.
 *
 * @var string
 */
$auth_secret = getenv('SMF_AUTH_SECRET') ?: '';

// Make sure the paths are correct... at least try to fix them.
if (! is_dir(realpath($boarddir)) && file_exists(dirname(__FILE__).'/agreement.txt')) {
    $boarddir = dirname(__FILE__);
}
if (! is_dir(realpath($sourcedir)) && is_dir($boarddir.'/Sources')) {
    $sourcedir = $boarddir.'/Sources';
}
if (! is_dir(realpath($tasksdir)) && is_dir($sourcedir.'/tasks')) {
    $tasksdir = $sourcedir.'/tasks';
}
if (! is_dir(realpath($packagesdir)) && is_dir($boarddir.'/Packages')) {
    $packagesdir = $boarddir.'/Packages';
}
if (! is_dir(realpath($cachedir)) && is_dir($boarddir.'/cache')) {
    $cachedir = $boarddir.'/cache';
}

//######## Legacy Settings #########
// UTF-8 is now the only character set supported in 2.1.
$db_character_set = 'utf8mb4';

//######### Error-Catching ##########
// Note: You shouldn't touch these settings.
if (file_exists(($cachedir ?? dirname(__FILE__)).'/db_last_error.php')) {
    include ($cachedir ?? dirname(__FILE__)).'/db_last_error.php';
}

if (! isset($db_last_error)) {
    // File does not exist so lets try to create it
    file_put_contents(($cachedir ?? dirname(__FILE__)).'/db_last_error.php', '<'.'?'."php\n".'$db_last_error = 0;'."\n".'?'.'>');
    $db_last_error = 0;
}

if (file_exists(dirname(__FILE__).'/install.php')) {
    $secure = false;
    if (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] == 'on') {
        $secure = true;
    } elseif (! empty($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https' || ! empty($_SERVER['HTTP_X_FORWARDED_SSL']) && $_SERVER['HTTP_X_FORWARDED_SSL'] == 'on') {
        $secure = true;
    }

    if (basename($_SERVER['PHP_SELF']) != 'install.php') {
        header('location: http'.($secure ? 's' : '').'://'.(empty($_SERVER['HTTP_HOST']) ? $_SERVER['SERVER_NAME'].(empty($_SERVER['SERVER_PORT']) || $_SERVER['SERVER_PORT'] == '80' ? '' : ':'.$_SERVER['SERVER_PORT']) : $_SERVER['HTTP_HOST']).(strtr(dirname($_SERVER['PHP_SELF']), '\\', '/') == '/' ? '' : strtr(dirname($_SERVER['PHP_SELF']), '\\', '/')).'/install.php');

        exit;
    }
}

//######### Themes ##########
$settings = $settings ?? [];
$settings['theme_default'] = 1;
$settings['theme_guests'] = 1;
$settings['default_theme_dir'] = $boarddir.'/Themes/default';
$settings['default_theme_url'] = $boardurl.'/Themes/default';
