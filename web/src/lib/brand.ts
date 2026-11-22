import type { CSSProperties } from 'react';
import type { ThemeMode } from './types';

/**
 * Marca del restaurante → variables CSS. Cada restaurante elige colores, modo claro/oscuro y
 * tipografía en la app (Ajustes → Apariencia) y la web los aplica sola.
 */

const HEX = /^#?([0-9a-f]{6})$/i;

function parse(hex: string): [number, number, number] | null {
  const m = HEX.exec(hex.trim());
  if (!m) return null;
  const n = parseInt(m[1], 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

const toHex = ([r, g, b]: [number, number, number]) =>
  '#' + [r, g, b].map((v) => Math.round(Math.min(255, Math.max(0, v))).toString(16).padStart(2, '0')).join('');

function luminance([r, g, b]: [number, number, number]) {
  const ch = (v: number) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b);
}

function contrast(a: [number, number, number], b: [number, number, number]) {
  const [l1, l2] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
}

const mix = (a: [number, number, number], b: [number, number, number], t: number): [number, number, number] => [
  a[0] + (b[0] - a[0]) * t,
  a[1] + (b[1] - a[1]) * t,
  a[2] + (b[2] - a[2]) * t,
];

/** Texto legible encima de un color (oscuro cálido o crema). */
function onColor(rgb: [number, number, number]) {
  const dark: [number, number, number] = [26, 12, 2];
  const light: [number, number, number] = [255, 250, 243];
  return contrast(rgb, dark) >= contrast(rgb, light) ? toHex(dark) : toHex(light);
}

/** El color de marca usado como texto: se ajusta hasta que se lea bien sobre el fondo. */
function readableOn(rgb: [number, number, number], bg: [number, number, number]) {
  const target: [number, number, number] = luminance(bg) < 0.2 ? [255, 255, 255] : [0, 0, 0];
  let c = rgb;
  for (let i = 0; i < 10 && contrast(c, bg) < 4.5; i++) c = mix(c, target, 0.15);
  return toHex(c);
}

const PALETTES: Record<ThemeMode, Record<string, string>> = {
  dark: {
    '--bg': '#120E0B',
    '--surface': '#1A1410',
    '--surface-2': '#221B15',
    '--surface-3': '#2C231C',
    '--line': 'rgba(255, 236, 214, 0.09)',
    '--line-strong': 'rgba(255, 236, 214, 0.16)',
    '--ink': '#F8F1E7',
    '--soft': '#CDBFAE',
    '--muted': '#A99A88',
    '--danger': '#FF6B5E',
    '--success': '#4ED29A',
    '--shadow': '0 18px 40px rgba(0, 0, 0, 0.5)',
  },
  light: {
    '--bg': '#FBF6F0',
    '--surface': '#FFFFFF',
    '--surface-2': '#F4ECE2',
    '--surface-3': '#EADFD2',
    '--line': 'rgba(60, 30, 5, 0.09)',
    '--line-strong': 'rgba(60, 30, 5, 0.18)',
    '--ink': '#1D150E',
    '--soft': '#55483B',
    '--muted': '#7C6D5E',
    '--danger': '#C8372D',
    '--success': '#16855A',
    '--shadow': '0 18px 40px rgba(60, 30, 5, 0.16)',
  },
};

export function brandStyle(input: { primaryColor?: string; accentColor?: string; themeMode?: string }): CSSProperties {
  const mode: ThemeMode = input.themeMode === 'light' ? 'light' : 'dark';
  const palette = PALETTES[mode];
  const bg = parse(palette['--bg'])!;
  const brand = parse(input.primaryColor ?? '') ?? [255, 122, 26];
  const accent = parse(input.accentColor ?? '') ?? [255, 194, 71];
  return {
    ...palette,
    '--brand': toHex(brand),
    '--on-brand': onColor(brand),
    '--brand-text': readableOn(brand, bg),
    '--brand-soft': `rgba(${brand.map(Math.round).join(', ')}, ${mode === 'dark' ? 0.14 : 0.12})`,
    '--accent': toHex(accent),
    '--on-accent': onColor(accent),
    '--accent-text': readableOn(accent, bg),
    colorScheme: mode,
  } as CSSProperties;
}
