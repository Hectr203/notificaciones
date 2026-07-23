# Despliegue con azd en Azure VPS economico

Esta opcion crea un VPS en Azure con `azd up`, instala Docker automaticamente y levanta Centrifugo + Caddy.

## Costo estimado

Configuracion recomendada para este repo:

- VM `Standard_B1s`: 1 vCPU y 1 GB RAM. Es mas estable para Docker + Caddy + Centrifugo.
- VM `Standard_B1ls`: 1 vCPU y 512 MB RAM. Es mas barata, pero puede no estar disponible o quedarse corta durante la instalacion.
- Disco `Standard_LRS` de 30 GB.
- IP publica Standard con DNS de Azure.
- Sin Redis, balanceador, Kubernetes, base de datos administrada ni App Service.

Estimacion realista con `Standard_B1s`: cerca de `180 a 280 MXN/mes`, dependiendo de region, tipo de cambio e impuestos. Azure cobra la IP publica IPv4; por eso puede quedar arriba de 200 MXN. Si necesitas forzar el rango `100 a 200 MXN`, prueba `Standard_B1ls`, pero no siempre esta disponible para la suscripcion.

## Requisitos locales

```bash
azd version
az version
ssh -V
```

Si no tienes llave SSH:

```bash
ssh-keygen -t ed25519 -C "azure-realtime" -f ~/.ssh/notis_realtime_azure
```

## Configurar ambiente

Desde la raiz del repo:

```bash
azd auth login
azd init --environment notis-prod
azd env set AZURE_LOCATION eastus
azd env set AZURE_VM_SIZE Standard_B1s
azd env set AZURE_SSH_PUBLIC_KEY "$(cat ~/.ssh/notis_realtime_azure.pub)"
azd env set CENTRIFUGO_TOKEN_SECRET "$(openssl rand -base64 48)"
azd env set CENTRIFUGO_HTTP_API_KEY "$(openssl rand -base64 32)"
azd env set CENTRIFUGO_ALLOWED_ORIGINS "https://tu-frontend.com"
```

Para intentar bajar costo, puedes usar `Standard_B1ls`:

```bash
azd env set AZURE_VM_SIZE Standard_B1ls
```

Si Azure responde `SkuNotAvailable` o la instalacion queda lenta, vuelve a `Standard_B1s`.

## Desplegar

```bash
azd up
```

Al terminar, `azd` mostrara salidas como:

```text
websocketUrl = wss://...cloudapp.azure.com/connection/websocket
httpApiUrl = https://...cloudapp.azure.com/api
sshCommand = ssh azureuser@...cloudapp.azure.com
```

## Verificar

```bash
curl https://DOMINIO_AZURE/health
ssh -i ~/.ssh/notis_realtime_azure azureuser@DOMINIO_AZURE
```

Dentro del VPS:

```bash
cd /opt/realtime
sudo docker compose ps
sudo docker compose logs -f --tail=100
free -m
df -h
```

## Variables para tu app

Frontend:

```env
CENTRIFUGO_WS_URL=wss://DOMINIO_AZURE/connection/websocket
```

Backend:

```env
CENTRIFUGO_HTTP_URL=http://centrifugo:8000
CENTRIFUGO_TOKEN_SECRET=el_mismo_valor_de_CENTRIFUGO_TOKEN_SECRET
CENTRIFUGO_HTTP_API_KEY=el_mismo_valor_de_CENTRIFUGO_HTTP_API_KEY
```

Backend externo al VPS:

```env
CENTRIFUGO_HTTP_URL=https://DOMINIO_AZURE/api
CENTRIFUGO_TOKEN_SECRET=el_mismo_valor_de_CENTRIFUGO_TOKEN_SECRET
CENTRIFUGO_HTTP_API_KEY=el_mismo_valor_de_CENTRIFUGO_HTTP_API_KEY
```

Para backend externo, Caddy solo deja pasar `/api` si el request trae `Authorization: apikey <CENTRIFUGO_HTTP_API_KEY>`. Sin ese header responde `403`. El backend debe publicar usando ese header, no `X-API-Key`, cuando consuma Centrifugo por el dominio publico.

La VM habilita el namespace `notifications` para canales `notifications:<userId>`, que es el formato usado por la aplicacion.

## Apagar o borrar para no cobrar

Para borrar todo y dejar de pagar recursos del ambiente:

```bash
azd down --purge --force
```
