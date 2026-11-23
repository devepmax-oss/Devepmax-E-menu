import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { cert, getApps, initializeApp, type App } from 'firebase-admin/app';
import { getMessaging, type Messaging } from 'firebase-admin/messaging';
import { loadEnv } from '../../config/env';
import { PrismaService } from '../../prisma/prisma.service';

export interface PushMessage {
  title: string;
  body: string;
  /** Datos para la app (todos texto). */
  data?: Record<string, string>;
  /** Pedidos nuevos: sonido propio, prioridad alta y no se descarta solo. */
  urgent?: boolean;
}

/** Códigos de Firebase que indican que el token ya no sirve (app desinstalada, permiso quitado). */
const DEAD_TOKEN = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

/**
 * Notificaciones push con Firebase Cloud Messaging. Es "mejor esfuerzo": si Firebase no está
 * configurado o falla, se registra en el log y la operación que la originó sigue normal
 * (el repartidor igual recibe el aviso en vivo si tiene la app abierta).
 */
@Injectable()
export class PushService implements OnModuleInit {
  private readonly logger = new Logger(PushService.name);
  private messaging?: Messaging | null;

  constructor(private readonly prisma: PrismaService) {}

  /** Al arrancar se ve en el log si las notificaciones quedaron activas. */
  onModuleInit() {
    this.client();
  }

  private client(): Messaging | null {
    if (this.messaging !== undefined) return this.messaging;
    const path = loadEnv().firebaseServiceAccountPath;
    if (!path) {
      this.logger.warn('Notificaciones push desactivadas: falta FIREBASE_SERVICE_ACCOUNT_PATH en .env');
      return (this.messaging = null);
    }
    try {
      const account = JSON.parse(readFileSync(resolve(path), 'utf8'));
      const app: App = getApps()[0] ?? initializeApp({ credential: cert(account) });
      this.messaging = getMessaging(app);
      this.logger.log(`Notificaciones push activas (Firebase: ${account.project_id})`);
    } catch (error) {
      this.logger.error(`No se pudo iniciar Firebase: ${String(error)}`);
      this.messaging = null;
    }
    return this.messaging;
  }

  get enabled(): boolean {
    return this.client() !== null;
  }

  /** Guarda (o mueve) el token de notificaciones de un dispositivo. */
  async register(subject: string, token: string, platform?: string) {
    await this.prisma.notificationToken.upsert({
      where: { token },
      create: { token, subject, platform, isActive: true },
      update: { subject, platform, isActive: true, lastSeenAt: new Date() },
    });
    return { ok: true, enabled: this.enabled };
  }

  async unregister(token: string) {
    await this.prisma.notificationToken.updateMany({ where: { token }, data: { isActive: false } });
    return { ok: true };
  }

  /** Envía a todos los dispositivos activos de un sujeto ("employee:<id>"). */
  async send(subject: string, message: PushMessage): Promise<number> {
    const messaging = this.client();
    if (!messaging) return 0;
    const tokens = (await this.prisma.notificationToken.findMany({ where: { subject, isActive: true }, select: { token: true } })).map(
      (t) => t.token,
    );
    if (!tokens.length) return 0;
    try {
      const result = await messaging.sendEachForMulticast({
        tokens,
        notification: { title: message.title, body: message.body },
        // Título y texto también en data: el service worker de la web los usa si hace falta.
        data: { ...(message.data ?? {}), title: message.title, body: message.body, urgent: message.urgent ? '1' : '0' },
        android: {
          priority: 'high',
          notification: message.urgent
            ? { channelId: 'pedidos', sound: 'nuevo_pedido', defaultVibrateTimings: true, visibility: 'public' }
            : { channelId: 'avisos' },
        },
        apns: { payload: { aps: { sound: message.urgent ? 'nuevo_pedido.caf' : 'default' } } },
        webpush: {
          headers: { Urgency: message.urgent ? 'high' : 'normal' },
          notification: { requireInteraction: !!message.urgent, tag: message.data?.tag, renotify: true },
        },
      });
      const dead = result.responses
        .map((r, i) => (!r.success && r.error && DEAD_TOKEN.has(r.error.code) ? tokens[i] : null))
        .filter((t): t is string => !!t);
      if (dead.length) await this.prisma.notificationToken.updateMany({ where: { token: { in: dead } }, data: { isActive: false } });
      return result.successCount;
    } catch (error) {
      this.logger.error(`No se pudo enviar la notificación: ${String(error)}`);
      return 0;
    }
  }
}
