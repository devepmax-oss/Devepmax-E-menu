/**
 * Opciones de marca que cada restaurante elige en Ajustes. Las apps y la web
 * traducen estas claves a su tema (fondo, tipografías, contraste).
 */
export const THEME_MODES = ['dark', 'light'] as const;
export type ThemeMode = (typeof THEME_MODES)[number];

/** Combinaciones tipográficas probadas (títulos + texto), todas de Google Fonts. */
export const FONT_PAIRS = ['bricolage-inter', 'fraunces-inter', 'dmserif-dmsans', 'oswald-inter', 'poppins'] as const;
export type FontPair = (typeof FONT_PAIRS)[number];
