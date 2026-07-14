# Implementacion de Centrifugo en Node.js

## Objetivo
Integrar Centrifugo como capa de tiempo real en un proyecto Node.js para:
- autenticar conexiones de clientes,
- suscribir usuarios a canales,
- publicar eventos desde el backend,
- recibir mensajes en el frontend en tiempo real.

## Arquitectura recomendada
Flujo correcto:
1. El usuario se autentica en tu app Node.
2. Tu backend genera un JWT de conexion para Centrifugo.
3. El frontend conecta al WebSocket de Centrifugo con ese token.
4. El frontend se suscribe a uno o varios canales.
5. Tu backend publica eventos a Centrifugo por HTTP API.
6. Centrifugo distribuye el evento a todos los suscriptores.

Regla practica:
- El cliente no debe publicar directamente si el mensaje requiere validacion de negocio.
- El backend decide que se publica.

## Requisitos
- Node.js 18 o superior.
- Un proceso de Centrifugo corriendo.
- Un secreto HMAC para tokens de cliente.
- Un `http_api.key` para publicar eventos desde backend.

## Variables de entorno
Usa algo asi:

```env
CENTRIFUGO_WS_URL=ws://127.0.0.1:8000/connection/websocket
CENTRIFUGO_HTTP_URL=http://127.0.0.1:8000
CENTRIFUGO_TOKEN_SECRET=tu_hmac_secret_key
CENTRIFUGO_HTTP_API_KEY=tu_http_api_key
APP_ORIGIN=http://localhost:3000
```

## Configuracion de Centrifugo
En desarrollo, el `config.json` debe incluir como minimo:

```json
{
  "client": {
    "token": {
      "hmac_secret_key": "TU_HMAC_SECRET"
    },
    "allowed_origins": ["http://localhost:3000"]
  },
  "http_api": {
    "key": "TU_HTTP_API_KEY"
  },
  "admin": {
    "enabled": true,
    "password": "una_password",
    "secret": "un_secret"
  },
  "channel": {
    "without_namespace": {
      "allow_subscribe_for_client": true
    }
  }
}
```

Notas:
- `allowed_origins` evita conexiones WebSocket desde orígenes no permitidos.
- `allow_subscribe_for_client` simplifica pruebas locales.
- En produccion conviene usar namespaces de canal.

## Instalacion en Node
Instala dependencias comunes:

```bash
npm i express jsonwebtoken centrifuge dotenv cors
```

Si usas `fetch` global de Node 18+, no necesitas librerias extra para publicar.

## Backend Node: generar token de conexion
Ejemplo con Express:

```js
import express from 'express';
import jwt from 'jsonwebtoken';
import cors from 'cors';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
app.use(cors({ origin: process.env.APP_ORIGIN }));
app.use(express.json());

app.get('/api/centrifugo-token', (req, res) => {
  // Sustituye esto por tu autenticacion real.
  const userId = '123';

  const token = jwt.sign(
    { sub: userId },
    process.env.CENTRIFUGO_TOKEN_SECRET,
    {
      algorithm: 'HS256',
      expiresIn: '1h',
    }
  );

  res.json({ token, userId });
});
```

Clave:
- El `sub` identifica al usuario.
- El token debe expirar.
- Genera el token solo para usuarios autenticados.

## Frontend: conectar y suscribirse
Ejemplo basico en navegador:

```html
<script src="https://unpkg.com/centrifuge@5.4.0/dist/centrifuge.js"></script>
<script>
  async function iniciarRealtime() {
    const r = await fetch('/api/centrifugo-token');
    const { token } = await r.json();

    const centrifuge = new Centrifuge('ws://127.0.0.1:8000/connection/websocket', {
      token,
    });

    centrifuge.on('connected', (ctx) => {
      console.log('conectado por', ctx.transport);
    });

    centrifuge.on('disconnected', (ctx) => {
      console.log('desconectado', ctx.code, ctx.reason);
    });

    centrifuge.connect();

    const sub = centrifuge.newSubscription('notificaciones');
    sub.on('publication', (ctx) => {
      console.log('evento recibido', ctx.data);
    });
    sub.subscribe();
  }

  iniciarRealtime();
</script>
```

## Publicar eventos desde Node
Tu backend publica al HTTP API de Centrifugo:

```js
app.post('/api/publicar', async (req, res) => {
  const payload = {
    channel: 'notificaciones',
    data: {
      mensaje: req.body.mensaje,
      timestamp: Date.now(),
    },
  };

  const resp = await fetch(`${process.env.CENTRIFUGO_HTTP_URL}/api/publish`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': process.env.CENTRIFUGO_HTTP_API_KEY,
    },
    body: JSON.stringify(payload),
  });

  if (!resp.ok) {
    const text = await resp.text();
    return res.status(502).json({ error: 'Centrifugo fallo', detail: text });
  }

  res.json({ ok: true });
});
```

## Ejemplo completo de flujo
1. Usuario crea un comentario.
2. Tu backend guarda el comentario en BD.
3. Tu backend publica el evento `comment.created` a `notificaciones`.
4. El frontend escucha ese canal y pinta el comentario en vivo.

## Ejemplo de canales
Opciones habituales:
- `notificaciones`
- `chat:123`
- `orden:456`

Si varios usuarios comparten contexto, usa un canal por entidad o por conversacion.

## Buenas practicas
- Usa un canal por dominio de negocio, no un canal global para todo.
- Expira los tokens de cliente.
- Mantén `http_api.key` solo en backend.
- No expongas `admin.insecure` en produccion.
- Si necesitas escalabilidad real, usa Redis o NATS como engine/broker.
- Si un evento es importante, persiste primero en tu BD y luego publica a Centrifugo.

## Seguridad minima para produccion
- Desactiva flags inseguros.
- Usa HTTPS/WSS.
- Limita `allowed_origins`.
- Autentica usuarios antes de emitir tokens.
- Protege el endpoint que publica eventos.

## Comandos utiles
Generar config:

```bash
./centrifugo genconfig
```

Levantar el servidor:

```bash
./centrifugo --config=config.json
```

Generar token manualmente:

```bash
./centrifugo gentoken -u 123
```

Publicar por API:

```bash
curl -X POST http://127.0.0.1:8000/api/publish \
  -H 'Content-Type: application/json' \
  -H 'X-API-Key: TU_HTTP_API_KEY' \
  -d '{"channel":"notificaciones","data":{"mensaje":"hola"}}'
```

## Checklist de implementacion
- [ ] Centrifugo corriendo.
- [ ] `config.json` con `hmac_secret_key` y `http_api.key`.
- [ ] `allowed_origins` configurado para tu frontend.
- [ ] Endpoint Node que emite token.
- [ ] Frontend conectado al WebSocket.
- [ ] Backend publicando eventos.
- [ ] Manejo de reconexion y errores en el cliente.
- [ ] Prueba manual publicando un evento y viendo la respuesta en vivo.

## Troubleshooting rapido
### No conecta el WebSocket
- Revisa `allowed_origins`.
- Verifica que el token sea valido y no haya expirado.
- Confirma la URL `ws://.../connection/websocket`.

### El backend publica pero no llega nada
- Verifica que el canal sea el mismo en frontend y backend.
- Revisa la respuesta del `POST /api/publish`.
- Confirma `X-API-Key` correcto.

### El admin UI no abre
- Asegura `admin.enabled=true`.
- En produccion, usa solo acceso protegido.

## Nota final
La forma correcta de usar Centrifugo en Node es tratarlo como transporte en tiempo real, no como fuente de verdad. La verdad debe vivir en tu backend y tu base de datos.
