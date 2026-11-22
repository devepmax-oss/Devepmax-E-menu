import { Logger, OnModuleDestroy } from '@nestjs/common';
import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import { Actor } from '../common/auth/actor';
import { AuthService } from '../modules/auth/auth.service';
import { DomainEvent, DomainEventsService } from './domain-events.service';
import { toPublicOrderView } from '../modules/orders/public-order.view';
import type { OrderView } from '../modules/orders/orders.service';
import { normalizeTrackCode, publicOrderRoom, Rooms, roomsForActor, roomsForEvent, secondsUntilExpiry } from './rooms';

interface SocketData {
  actor: Actor;
  /** Cliente de la web siguiendo su pedido (sin cuenta): solo entra a order:<código>. */
  trackCode: string;
  expiryTimer?: NodeJS.Timeout;
}

type AppSocket = Socket & { data: Partial<SocketData> };

/** setTimeout no acepta más de ~24 días. */
const MAX_TIMER_MS = 2_147_000_000;

/**
 * Tiempo real (Socket.IO, ruta /socket.io).
 *
 * - El socket se autentica con el mismo token que la API: `io(url, { auth: { token } })`.
 * - El servidor decide las rooms según permisos o tipo de dispositivo.
 * - Al conectarse (y en cada reconexión) el servidor manda `ready`: es la señal para que la app
 *   vuelva a pedir su lista completa (GET /orders?scope=active o GET /kitchen/tickets) y la reemplace.
 * - Cada orden, ticket y cuenta trae `updatedAt`: la app ignora un evento más viejo que lo que ya tiene.
 * - La web del cliente se conecta sin cuenta con `io(url, { auth: { track: '<código>' } })`:
 *   solo entra a la room de su pedido y solo recibe `order.public` (sin teléfono, email ni dirección).
 * - Si el token de acceso vence, el servidor manda `session.expired` y desconecta: la app renueva
 *   el token y se vuelve a conectar.
 */
@WebSocketGateway()
export class RealtimeGateway implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect, OnModuleDestroy {
  private readonly logger = new Logger(RealtimeGateway.name);
  private unsubscribe?: () => void;

  @WebSocketServer()
  private server!: Server;

  constructor(
    private readonly auth: AuthService,
    private readonly events: DomainEventsService,
  ) {}

  afterInit(server: Server): void {
    // Autenticación antes de aceptar la conexión: sin token válido no hay socket.
    server.use((socket, next) => {
      const token = extractSocketToken(socket);
      if (!token) {
        const trackCode = normalizeTrackCode((socket.handshake.auth as { track?: unknown } | undefined)?.track);
        if (!trackCode) return next(new Error('Autenticación requerida'));
        (socket as AppSocket).data.trackCode = trackCode;
        return next();
      }
      this.auth
        .resolveActor(token)
        .then((actor) => {
          (socket as AppSocket).data.actor = actor;
          scheduleExpiry(socket as AppSocket, token);
          next();
        })
        .catch(() => next(new Error('Token inválido o vencido')));
    });

    this.unsubscribe = this.events.subscribe((event) => this.handleDomainEvent(event));
  }

  async handleConnection(socket: AppSocket): Promise<void> {
    const { actor, trackCode } = socket.data;
    if (!actor && trackCode) {
      const room = Rooms.order(trackCode);
      await socket.join(room);
      socket.emit('ready', { rooms: [room], serverTime: new Date().toISOString() });
      return;
    }
    if (!actor) {
      socket.disconnect(true);
      return;
    }
    const rooms = roomsForActor(actor);
    await socket.join(rooms);
    socket.emit('ready', {
      rooms: rooms.filter((r) => !r.startsWith('device:') && !r.startsWith('employee:')),
      serverTime: new Date().toISOString(),
    });
  }

  handleDisconnect(socket: AppSocket): void {
    if (socket.data.expiryTimer) clearTimeout(socket.data.expiryTimer);
  }

  onModuleDestroy(): void {
    this.unsubscribe?.();
  }

  private handleDomainEvent(event: DomainEvent): void {
    if (!this.server) return;

    if (event.name === 'device.changed') {
      const { deviceId } = event.payload as { deviceId: string };
      this.server.in(Rooms.device(deviceId)).disconnectSockets(true);
      return;
    }
    if (event.name === 'employee.changed') {
      const { employeeId } = event.payload as { employeeId: string };
      this.server.in(Rooms.employee(employeeId)).disconnectSockets(true);
      return;
    }

    const trackRoom = publicOrderRoom(event);
    if (trackRoom) {
      try {
        const view = toPublicOrderView(event.payload as OrderView);
        this.server.to(trackRoom).emit('order.public', JSON.parse(JSON.stringify(view)));
      } catch (error) {
        this.logger.error(`No se pudo difundir order.public: ${String(error)}`);
      }
    }

    const rooms = roomsForEvent(event);
    if (!rooms.length) return;
    try {
      // Igual que en la API REST: decimales como texto y fechas en ISO.
      const payload: unknown = JSON.parse(JSON.stringify(event.payload));
      this.server.to(rooms).emit(event.name, payload);
    } catch (error) {
      this.logger.error(`No se pudo difundir ${event.name}: ${String(error)}`);
    }
  }
}

/** Token en `auth.token` (navegador y apps) o en el encabezado Authorization (otras herramientas). */
export function extractSocketToken(socket: Pick<Socket, 'handshake'>): string | undefined {
  const fromAuth = (socket.handshake.auth as { token?: unknown } | undefined)?.token;
  if (typeof fromAuth === 'string' && fromAuth.trim()) return fromAuth.trim().replace(/^Bearer\s+/i, '');
  const header = socket.handshake.headers.authorization;
  if (typeof header === 'string') {
    const [scheme, token] = header.split(' ');
    if (scheme?.toLowerCase() === 'bearer' && token) return token.trim();
  }
  return undefined;
}

/** Los tokens de empleado vencen: al vencer se avisa y se cierra el socket. Los de dispositivo no vencen. */
function scheduleExpiry(socket: AppSocket, token: string): void {
  const seconds = secondsUntilExpiry(token);
  if (seconds === undefined) return;
  const ms = Math.min(Math.max(seconds, 0) * 1000, MAX_TIMER_MS);
  socket.data.expiryTimer = setTimeout(() => {
    socket.emit('session.expired');
    socket.disconnect(true);
  }, ms);
}
