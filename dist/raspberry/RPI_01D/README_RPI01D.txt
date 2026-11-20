ADN MyCarWash RPI-01D | Integración de kiosco sin secreto en URL

OBJETIVO: Mantener la misma Vista general de lavados del administrador.
Raspberry Pi: Chromium abre automaticamente http://127.0.0.1:8787/?mcw_kiosk=local.
El valor 'local' NO es un secreto. Un proxy local de solo lectura lee device.key (0600)
e inyecta X-MCW-Kiosk-Key unicamente en cuatro endpoints GET especificos de Laravel.
Nunca se usa sesión del propietario para las consultas de monitoreo.

Paso 1: Ejecutar PreflightOnly y ApplyLocal en Windows, compilar Flutter Web.
Paso 2: Ejecutar HostPreflight; solo si coincide con las fuentes auditadas, Deploy.
Paso 3: Emitir clave de dispositivo desde cuenta owner (API REST existente)
    POST https://mycarwash.adnpublicidad.site/api/index.php/api/v1/companies/1/monitor-devices-rpi01c
    JSON {"branch_id": 1,"name":"TV Lavados Raspberry 3"}
    Authorization: Bearer <TOKEN_DE_OWNER> (NO incluir en capturas ni registros).
    Confirmar que branch_id es la sucursal correcta; el ejemplo no es una asignación segura.
    La API devuelve la clave una sola vez; guardarla solo en Raspberry.
Paso 4: Raspberry Pi OS Desktop con labwc y Chromium instalados; copiar
    MCW_RPI_01D_Instalar_Raspberry.sh y mcw_kiosk_proxy.py a la misma carpeta.
    bash MCW_RPI_01D_Instalar_Raspberry.sh --preflight
    bash MCW_RPI_01D_Instalar_Raspberry.sh --apply
    Configurar Desktop Autologin una sola vez en raspi-config y reiniciar.
Paso 5: Verificar muestra, fotos, cola, finalización 10s, revocación y aislamiento.

IMPORTANTE: el endpoint de logo del kiosco está desactivado deliberadamente
hasta tener el controlador BusinessLogoController y su esquema de almacenamiento.
La interfaz mostrará el logo de reserva definido en Flutter. No se suplanta owner.
La integración del panel visual de alta/revocación también está pendiente.

SEGURIDAD: No pasar contraseñas ni claves en URL, en archivos públicos,
ni en capturas. El acceso físico a Raspberry debe estar controlado.
La navegación local se limita a 127.0.0.1; no abrir puerto 8787 a la LAN.

La migración requiere revisión del despliegue y respaldo de BD antes de producción.
