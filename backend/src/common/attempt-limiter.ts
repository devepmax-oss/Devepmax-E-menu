import { HttpException, HttpStatus } from '@nestjs/common';

/**
 * Limita intentos fallidos por clave (IP + usuario, dispositivo, etc.) en memoria.
 * Suficiente para una instalación por restaurante con un solo proceso.
 */
export class AttemptLimiter {
  private readonly attempts = new Map<string, { count: number; firstAt: number }>();

  constructor(
    private readonly maxFailures: number,
    private readonly windowMs: number,
    private readonly now: () => number = Date.now,
  ) {}

  assertAllowed(key: string): void {
    const entry = this.current(key);
    if (entry && entry.count >= this.maxFailures) {
      throw new HttpException(
        'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }

  fail(key: string): void {
    const entry = this.current(key);
    if (entry) entry.count += 1;
    else this.attempts.set(key, { count: 1, firstAt: this.now() });
  }

  reset(key: string): void {
    this.attempts.delete(key);
  }

  private current(key: string) {
    const entry = this.attempts.get(key);
    if (entry && this.now() - entry.firstAt > this.windowMs) {
      this.attempts.delete(key);
      return undefined;
    }
    return entry;
  }
}
