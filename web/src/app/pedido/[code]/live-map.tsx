'use client';

import 'leaflet/dist/leaflet.css';
import type { Map as LeafletMap, Marker } from 'leaflet';
import { useEffect, useRef } from 'react';

type Point = { lat: number; lng: number };

const pin = (html: string, size = 40) => ({ html, className: '', iconSize: [size, size] as [number, number], iconAnchor: [size / 2, size / 2] as [number, number] });

const STORE = `<div style="width:36px;height:36px;border-radius:999px;background:var(--bg);border:3px solid var(--accent);display:flex;align-items:center;justify-content:center;box-shadow:0 6px 16px rgba(0,0,0,.4)"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--accent)" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M3 9l1.5-5h15L21 9"/><path d="M4 9v11h16V9"/><path d="M9 20v-6h6v6"/></svg></div>`;
const HOME = `<div style="width:40px;height:40px;border-radius:999px;background:var(--ink);display:flex;align-items:center;justify-content:center;box-shadow:0 6px 16px rgba(0,0,0,.4)"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--bg)" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M3 11l9-7 9 7"/><path d="M5 10v10h14V10"/></svg></div>`;
const DRIVER = `<div style="position:relative;width:44px;height:44px"><span class="live" style="position:absolute;inset:-8px;border-radius:999px;background:var(--brand);opacity:.25"></span><div style="position:absolute;inset:0;border-radius:999px;background:var(--brand);border:4px solid var(--bg);display:flex;align-items:center;justify-content:center;box-shadow:0 8px 20px rgba(0,0,0,.45)"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--on-brand)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="5.5" cy="17.5" r="3.5"/><circle cx="18.5" cy="17.5" r="3.5"/><path d="M15 6h2l3 7.5M5.5 17.5l3-7h6l3.5 7"/></svg></div></div>`;

/**
 * Mapa en vivo (OpenStreetMap, gratis y sin clave): local, destino aproximado y repartidor.
 * El repartidor se mueve solo cuando llega una ubicación nueva.
 */
export function LiveMap({ driver, destination, store }: { driver: Point | null; destination: Point | null; store: Point | null }) {
  const box = useRef<HTMLDivElement>(null);
  const map = useRef<LeafletMap | null>(null);
  const driverMarker = useRef<Marker | null>(null);
  const fitted = useRef(false);
  const leaflet = useRef<typeof import('leaflet') | null>(null);

  // Crear el mapa una vez.
  useEffect(() => {
    let cancelled = false;
    import('leaflet').then((L) => {
      if (cancelled || !box.current || map.current) return;
      leaflet.current = L;
      const m = L.map(box.current, { zoomControl: false, attributionControl: true, scrollWheelZoom: false });
      L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
      }).addTo(m);
      if (store) L.marker([store.lat, store.lng], { icon: L.divIcon(pin(STORE, 36)), keyboard: false }).addTo(m);
      if (destination) L.marker([destination.lat, destination.lng], { icon: L.divIcon(pin(HOME, 40)), keyboard: false }).addTo(m);
      const start = driver ?? destination ?? store;
      if (start) m.setView([start.lat, start.lng], 15);
      map.current = m;
      setTimeout(() => m.invalidateSize(), 50);
    });
    return () => {
      cancelled = true;
      map.current?.remove();
      map.current = null;
      driverMarker.current = null;
      fitted.current = false;
    };
    // El local y el destino no cambian durante el seguimiento.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Mover al repartidor y encuadrar la primera vez.
  useEffect(() => {
    const L = leaflet.current;
    const m = map.current;
    if (!L || !m || !driver) return;
    if (!driverMarker.current) {
      driverMarker.current = L.marker([driver.lat, driver.lng], { icon: L.divIcon(pin(DRIVER, 44)), keyboard: false, zIndexOffset: 1000 }).addTo(m);
    } else {
      driverMarker.current.setLatLng([driver.lat, driver.lng]);
    }
    if (!fitted.current) {
      const points = [driver, destination].filter(Boolean) as Point[];
      if (points.length > 1) m.fitBounds(L.latLngBounds(points.map((p) => [p.lat, p.lng])), { padding: [60, 60], maxZoom: 16 });
      else m.setView([driver.lat, driver.lng], 16);
      fitted.current = true;
    }
  }, [driver, destination]);

  return <div ref={box} className="absolute inset-0 z-0" role="img" aria-label="Mapa con la ubicación del repartidor" />;
}
