import { Bricolage_Grotesque, DM_Sans, DM_Serif_Display, Fraunces, Inter, Oswald, Poppins } from 'next/font/google';

// Las 5 combinaciones que el restaurante puede elegir en Ajustes → Apariencia.
// El navegador solo descarga las fuentes de la combinación elegida.
const bricolage = Bricolage_Grotesque({ subsets: ['latin'], variable: '--font-bricolage', display: 'swap' });
const inter = Inter({ subsets: ['latin'], variable: '--font-inter', display: 'swap' });
const fraunces = Fraunces({ subsets: ['latin'], variable: '--font-fraunces', display: 'swap' });
const dmSerif = DM_Serif_Display({ subsets: ['latin'], weight: '400', variable: '--font-dmserif', display: 'swap' });
const dmSans = DM_Sans({ subsets: ['latin'], variable: '--font-dmsans', display: 'swap' });
const oswald = Oswald({ subsets: ['latin'], variable: '--font-oswald', display: 'swap' });
const poppins = Poppins({ subsets: ['latin'], weight: ['400', '500', '600', '700', '800'], variable: '--font-poppins', display: 'swap' });

type Font = { variable: string };
const PAIRS: Record<string, { heading: Font; body: Font; headingVar: string; bodyVar: string }> = {
  'bricolage-inter': { heading: bricolage, body: inter, headingVar: '--font-bricolage', bodyVar: '--font-inter' },
  'fraunces-inter': { heading: fraunces, body: inter, headingVar: '--font-fraunces', bodyVar: '--font-inter' },
  'dmserif-dmsans': { heading: dmSerif, body: dmSans, headingVar: '--font-dmserif', bodyVar: '--font-dmsans' },
  'oswald-inter': { heading: oswald, body: inter, headingVar: '--font-oswald', bodyVar: '--font-inter' },
  poppins: { heading: poppins, body: poppins, headingVar: '--font-poppins', bodyVar: '--font-poppins' },
};

/** Clases y variables CSS para la tipografía elegida. */
export function fontPair(id: string) {
  const pair = PAIRS[id] ?? PAIRS['bricolage-inter'];
  const className = [...new Set([pair.heading.variable, pair.body.variable])].join(' ');
  return {
    className,
    style: {
      '--font-heading': `var(${pair.headingVar})`,
      '--font-body': `var(${pair.bodyVar})`,
    } as Record<string, string>,
  };
}
