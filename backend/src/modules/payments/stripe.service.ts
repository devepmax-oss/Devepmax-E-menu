import { BadRequestException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import Stripe from 'stripe';
import { loadEnv } from '../../config/env';

/** Acceso a Stripe. Si no hay claves en .env, los pagos en línea quedan desactivados. */
@Injectable()
export class StripeService {
  private client?: Stripe;

  get configured(): boolean {
    return !!loadEnv().stripe.secretKey;
  }

  /** Clave pública para el navegador (no es secreta). */
  get publishableKey(): string | null {
    return loadEnv().stripe.publishableKey ?? null;
  }

  private get stripe(): Stripe {
    const key = loadEnv().stripe.secretKey;
    if (!key) throw new ServiceUnavailableException('Los pagos en línea no están configurados');
    this.client ??= new Stripe(key);
    return this.client;
  }

  /** Modo prueba (claves sk_test_): permite el lector simulado. */
  get testMode(): boolean {
    return (loadEnv().stripe.secretKey ?? '').startsWith('sk_test_');
  }

  /** Cliente de Stripe (Terminal: ubicaciones, lectores, cobros presenciales). */
  get api(): Stripe {
    return this.stripe;
  }

  createPaymentIntent(params: Stripe.PaymentIntentCreateParams, idempotencyKey: string) {
    return this.stripe.paymentIntents.create(params, { idempotencyKey });
  }

  retrievePaymentIntent(id: string) {
    return this.stripe.paymentIntents.retrieve(id);
  }

  /** Verifica la firma de un aviso de Stripe (webhook). */
  constructEvent(rawBody: Buffer, signature: string): Stripe.Event {
    const secret = loadEnv().stripe.webhookSecret;
    if (!secret) throw new ServiceUnavailableException('El webhook de Stripe no está configurado');
    try {
      return this.stripe.webhooks.constructEvent(rawBody, signature, secret);
    } catch {
      throw new BadRequestException('Firma de Stripe inválida');
    }
  }
}
