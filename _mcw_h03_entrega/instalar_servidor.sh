#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
SITE="$HOME/domains/mycarwash.adnpublicidad.site"
WEB="$SITE/public_html"
UPLOAD="$HOME/.mcw_h03_upload"
PHP=/opt/alt/php84/usr/bin/php
APP="$SITE/application"
STAMP="$(date +%Y%m%d_%H%M%S)"
STAGE="$SITE/.mcw_stage_$STAMP"
BACKUP="$SITE/.mcw_backup_$STAMP"
trap 'echo "[ERROR] Instalacion interrumpida en linea $LINENO; revisar el estado antes de reintentar." >&2' ERR
for f in "$UPLOAD/backend.tgz" "$UPLOAD/frontend.tgz"; do [[ -s "$f" ]] || { echo "[ERROR] Falta $f"; exit 1; }; done
[[ -x "$PHP" ]] || { echo '[ERROR] PHP 8.4 ausente';exit 1; }
[[ -d "$WEB" ]] || { echo '[ERROR] Directorio publico ausente';exit 1; }
mkdir -p "$STAGE/app" "$STAGE/web"
tar -xzf "$UPLOAD/backend.tgz" -C "$STAGE/app"
tar -xzf "$UPLOAD/frontend.tgz" -C "$STAGE/web"
[[ -f "$STAGE/app/artisan" && -f "$STAGE/web/index.html" ]] || { echo '[ERROR] Paquetes invalidos'; exit 1; }
[[ -f "$STAGE/app/composer.lock" ]] || { echo '[ERROR] composer.lock ausente'; exit 1; }
mkdir -p "$STAGE/app/storage/framework/cache/data" "$STAGE/app/storage/framework/sessions" "$STAGE/app/storage/framework/views" "$STAGE/app/storage/logs" "$STAGE/app/storage/app/public" "$STAGE/app/bootstrap/cache"
if [[ -f "$APP/.env" ]]; then cp -p "$APP/.env" "$STAGE/app/.env"; elif [[ -f "$STAGE/app/.env.example" ]]; then cp "$STAGE/app/.env.example" "$STAGE/app/.env"; else echo '[ERROR] No hay plantilla .env.example';exit 1; fi
read -r -p 'Nombre completo de base [u266120157_mycarwash]: ' DB_NAME
DB_NAME="${DB_NAME:-u266120157_mycarwash}"
read -r -p 'Usuario MySQL [u266120157_mcw_admin]: ' DB_USER
DB_USER="${DB_USER:-u266120157_mcw_admin}"
read -r -s -p 'Contrasena MySQL (no se muestra): ' DB_PASS;echo
[[ -n "$DB_PASS" ]] || { echo '[ERROR] Contrasena vacia'; exit 1; }
export MCW_DB_NAME="$DB_NAME" MCW_DB_USER="$DB_USER" MCW_DB_PASS="$DB_PASS"
"$PHP" -r '
$p=$argv[1];$x=file_get_contents($p);if($x===false)exit(1);
$v=["APP_NAME"=>"MyCarWash","APP_ENV"=>"production","APP_DEBUG"=>"false","APP_URL"=>"https://mycarwash.adnpublicidad.site","DB_CONNECTION"=>"mysql","DB_HOST"=>"localhost","DB_PORT"=>"3306","DB_DATABASE"=>getenv("MCW_DB_NAME"),"DB_USERNAME"=>getenv("MCW_DB_USER"),"DB_PASSWORD"=>getenv("MCW_DB_PASS"),"SESSION_DRIVER"=>"file","CACHE_STORE"=>"file","QUEUE_CONNECTION"=>"sync"];
foreach($v as $k=>$value){$val=($k==="APP_DEBUG"||$k==="DB_PORT")?$value:json_encode((string)$value,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES);$line=$k."=".$val;$rx="/^".preg_quote($k,"/")."=.*/m";if(preg_match($rx,$x)){$x=preg_replace($rx,static fn()=>$line,$x,1);}else{$x.="\n".$line;}}
if(file_put_contents($p,$x)===false)exit(2);
' "$STAGE/app/.env"
unset DB_PASS MCW_DB_PASS
chmod 600 "$STAGE/app/.env"
# Composer debe usar el PHP de MyCarWash, nunca el PHP global del alojamiento.
BIN="$STAGE/.bin";mkdir -p "$BIN";ln -s "$PHP" "$BIN/php"
export PATH="$BIN:$PATH" COMPOSER_MEMORY_LIMIT=-1
command -v composer >/dev/null || { echo '[ERROR] Composer no disponible'; exit 1; }
cd "$STAGE/app"
composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader
if ! grep -Eq '^APP_KEY=(.+[^"[:space:]]|".+")$' "$STAGE/app/.env"; then
  "$PHP" artisan key:generate --force --no-interaction
else
  echo '[INFO] APP_KEY previa conservada.'
fi
"$PHP" artisan config:clear
"$PHP" artisan route:list --path=api >/dev/null
# Validar DB y migraciones disponibles sin modificarlas todavia.
"$PHP" -r '$e=parse_ini_file($argv[1],false,INI_SCANNER_RAW);$p=trim($e["DB_PASSWORD"]??"","\"\x27");try{$db=new PDO("mysql:host=localhost;dbname=".trim($e["DB_DATABASE"],"\""),trim($e["DB_USERNAME"],"\""),$p,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);echo "[OK] Conexion PDO MySQL\n";}catch(Throwable $t){fwrite(STDERR,"[ERROR] PDO MySQL: ".$t->getMessage()."\n");exit(1);}' "$STAGE/app/.env"
echo '[INFO] Dependencias, rutas y base de datos: verificadas.'
echo '[INFO] Los archivos anteriores seran respaldados antes de activar.'
read -r -p 'Escriba PUBLICAR para activar Flutter + Laravel: ' confirm
[[ "$confirm" == 'PUBLICAR' ]] || { echo '[INFO] Sin publicar. El staging permanece para diagnostico.'; exit 0; }
mkdir -p "$BACKUP"
if [[ -d "$APP" ]]; then mv "$APP" "$BACKUP/application";fi
mv "$STAGE/app" "$APP"
mkdir -p "$BACKUP/public_html"
# Preservar .htaccess e instalar SPA; respaldar todo el directorio publico existente.
for f in "$WEB"/* "$WEB"/.[!.]* "$WEB"/..?*;do
  [[ -e "$f" || -L "$f" ]] || continue
  mv "$f" "$BACKUP/public_html/"
done
cp -a "$STAGE/web/." "$WEB/"
mkdir -p "$WEB/api"
cat > "$WEB/api/index.php" <<'PHPENTRY'
<?php
define('LARAVEL_START', microtime(true));
$application = dirname(__DIR__, 2) . '/application';
if (file_exists($maintenance = $application . '/storage/framework/maintenance.php')) require $maintenance;
require $application . '/vendor/autoload.php';
$app = require_once $application . '/bootstrap/app.php';
$app->handleRequest(Illuminate\Http\Request::capture());
PHPENTRY
cat > "$WEB/.htaccess" <<'HTACCESS'
<FilesMatch "\.(php4|php5|php3|php2|php|phtml)$">
 SetHandler application/x-lsphp84
</FilesMatch>
<IfModule mod_rewrite.c>
 RewriteEngine On
 RewriteRule ^api/index\.php$ - [L]
 RewriteRule ^api(?:/.*)?$ api/index.php [L,QSA]
 RewriteCond %{REQUEST_FILENAME} !-f
 RewriteCond %{REQUEST_FILENAME} !-d
 RewriteRule ^ /index.html [L]
</IfModule>
HTACCESS
ln -s "$APP/storage/app/public" "$WEB/storage" 2>/dev/null || true
cd "$APP"
"$PHP" artisan config:clear
"$PHP" artisan view:cache || true
echo '[INFO] Codigo publicado. Respaldos:' "$BACKUP"
echo '[INFO] Proximo paso: migraciones de base de datos.'
read -r -p 'Escriba MIGRAR para ejecutar php artisan migrate --force (crea/modifica tablas): ' mig
if [[ "$mig" == 'MIGRAR' ]];then "$PHP" artisan migrate --force;else echo '[INFO] Migraciones NO ejecutadas. La app puede no funcionar hasta migrar.';fi
printf '[INFO] HTTP frontend: ';curl -L -s -o /dev/null -w '%{http_code}\n' 'https://mycarwash.adnpublicidad.site/' || true
printf '[INFO] HTTP API: ';curl -L -s -o /dev/null -w '%{http_code}\n' 'https://mycarwash.adnpublicidad.site/api/v1/' || true
echo '[INFO] Instalacion terminada. Verificar inicio de sesion y permisos desde navegador; HTTP 404 en /api/v1/ no implica que la API este averiada.'
