# Infraestructura economica para WebSockets

Esta plantilla levanta Centrifugo detras de Caddy en un solo VPS barato. Caddy emite HTTPS automaticamente, por lo que el cliente usa `wss://` sin pagar un balanceador.

## Presupuesto recomendado: 100 a 200 MXN/mes

- VPS 1 vCPU / 1 GB RAM: aprox. 100 a 200 MXN al mes segun proveedor.
- Dominio: si ya tienes uno, costo mensual 0; si no, suele ser pago anual.
- SSL/HTTPS: 0 MXN con Caddy y Let's Encrypt.
- Total objetivo: mantenerlo entre 100 y 200 MXN al mes.

Evita Kubernetes, Redis administrado y balanceadores cloud mientras el trafico sea pequeno. Esta configuracion usa una sola instancia y engine en memoria.

## Tamano exacto del VPS

Compra el plan mas pequeno que cumpla esto:

- 1 vCPU.
- 1 GB RAM.
- 20 GB SSD o NVMe.
- 1 TB de transferencia o mas.
- Ubuntu 22.04/24.04 LTS o Debian 12.

No pagues por IP adicional, backups administrados, paneles tipo cPanel, base de datos administrada, Kubernetes, balanceador ni Redis al inicio.

## Distribucion de recursos

La plantilla limita recursos para que quepa en 1 GB RAM:

- Centrifugo: hasta `384 MB` y `0.70 CPU`.
- Caddy: hasta `128 MB` y `0.30 CPU`.
- Sistema operativo y Docker: resto de memoria.
- Swap recomendado: `1 GB` para evitar caidas por picos pequenos.

Esto deja margen para ejecutar tambien un backend Node pequeno en el mismo VPS si no consume demasiada memoria.

## Requisitos

- Un VPS Ubuntu/Debian con Docker y Docker Compose.
- Un dominio o subdominio apuntando al IP publico del VPS.
- Puertos `80` y `443` abiertos.

## Preparar VPS nuevo

En Ubuntu, puedes ejecutar como `root`:

```bash
sh server-setup.sh
```

Este script instala Docker, activa firewall basico, abre solo SSH/HTTP/HTTPS, activa actualizaciones de seguridad y crea `1 GB` de swap.

## Despliegue

1. Copia `.env.example` a `.env`.
2. Cambia `REALTIME_DOMAIN`, `CENTRIFUGO_CLIENT_ALLOWED_ORIGINS`, `CENTRIFUGO_CLIENT_TOKEN_HMAC_SECRET_KEY` y `CENTRIFUGO_HTTP_API_KEY`.
3. Levanta los servicios:

```bash
docker compose up -d
```

4. Verifica salud:

```bash
curl https://TU_DOMINIO/health
```

## Operacion barata

Comandos utiles para no pagar servicios extra:

```bash
docker compose logs -f --tail=100
docker compose ps
docker stats
df -h
free -m
```

La rotacion de logs ya esta configurada en Docker Compose para evitar que el disco se llene.

## Variables para tu aplicacion

Frontend:

```env
CENTRIFUGO_WS_URL=wss://TU_DOMINIO/connection/websocket
```

Backend en el mismo VPS y misma red Docker:

```env
CENTRIFUGO_HTTP_URL=http://centrifugo:8000
CENTRIFUGO_TOKEN_SECRET=EL_MISMO_VALOR_DE_CENTRIFUGO_CLIENT_TOKEN_HMAC_SECRET_KEY
CENTRIFUGO_HTTP_API_KEY=EL_MISMO_VALOR_DE_CENTRIFUGO_HTTP_API_KEY
```

Backend externo al VPS:

```env
CENTRIFUGO_HTTP_URL=https://TU_DOMINIO/api
CENTRIFUGO_TOKEN_SECRET=EL_MISMO_VALOR_DE_CENTRIFUGO_CLIENT_TOKEN_HMAC_SECRET_KEY
CENTRIFUGO_HTTP_API_KEY=EL_MISMO_VALOR_DE_CENTRIFUGO_HTTP_API_KEY
```

Caddy solo deja pasar `/api` si el request trae `Authorization: apikey <CENTRIFUGO_HTTP_API_KEY>`. Sin ese header responde `403`. El backend debe publicar usando ese header, no `X-API-Key`, cuando consuma Centrifugo por el dominio publico.

## Seguridad incluida

- `/api` queda expuesto solo con `Authorization: apikey <CENTRIFUGO_HTTP_API_KEY>`.
- `/metrics`, `/debug` y `/swagger` quedan bloqueados desde Internet en Caddy.
- El admin UI de Centrifugo queda desactivado.
- Solo se aceptan clientes con JWT firmado por tu backend.
- `allowed_origins` limita desde que dominios se puede abrir el WebSocket.
- El namespace `notifications` queda habilitado para canales `notifications:<userId>`.

## Cuando escalar

Mantener esta version mientras sea una sola instancia. Agrega Redis solo si necesitas mas de un Centrifugo, recuperacion de mensajes entre reinicios o mas resiliencia; eso aumenta costo y complejidad.

Senales de que ya no alcanza el VPS de 100 a 200 MXN:

- CPU arriba de 80% de forma sostenida.
- RAM casi llena y uso constante de swap.
- Muchas desconexiones WebSocket sin cambios de red.
- Necesitas alta disponibilidad real.

Mientras no pase eso, no escales.
