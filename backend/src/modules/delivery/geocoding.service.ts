import { Injectable, Logger } from '@nestjs/common';

/**
 * Convierte una dirección en coordenadas con OpenStreetMap (Nominatim), gratis y sin clave.
 * Es "mejor esfuerzo": si falla, el pedido sigue igual y el mapa muestra solo al repartidor.
 * Nominatim pide máximo 1 consulta por segundo y un User-Agent que identifique la app.
 */
@Injectable()
export class GeocodingService {
  private readonly logger = new Logger(GeocodingService.name);
  private queue: Promise<unknown> = Promise.resolve();
  private lastCall = 0;

  geocode(address: { street: string; city: string; state: string; zipCode: string }, contact?: string | null) {
    const run = async (): Promise<{ lat: number; lng: number } | null> => {
      const wait = this.lastCall + 1100 - Date.now();
      if (wait > 0) await new Promise((r) => setTimeout(r, wait));
      this.lastCall = Date.now();
      const params = new URLSearchParams({
        street: address.street,
        city: address.city,
        state: address.state,
        postalcode: address.zipCode,
        countrycodes: 'us',
        format: 'jsonv2',
        limit: '1',
      });
      try {
        const res = await fetch(`https://nominatim.openstreetmap.org/search?${params}`, {
          headers: { 'User-Agent': `DevepmaxEMenu/1.0${contact ? ` (${contact})` : ''}`, 'Accept-Language': 'en' },
          signal: AbortSignal.timeout(5000),
        });
        if (!res.ok) return null;
        const [hit] = (await res.json()) as { lat: string; lon: string }[];
        if (!hit) return null;
        const lat = Number(hit.lat);
        const lng = Number(hit.lon);
        return Number.isFinite(lat) && Number.isFinite(lng) ? { lat, lng } : null;
      } catch (error) {
        this.logger.warn(`No se pudo ubicar la dirección en el mapa: ${String(error)}`);
        return null;
      }
    };
    const next = this.queue.then(run, run);
    this.queue = next.catch(() => undefined);
    return next;
  }
}
