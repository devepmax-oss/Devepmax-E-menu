import { keyFromPublicUrl } from './storage.driver';

describe('keyFromPublicUrl', () => {
  const base = 'https://img.example.com';

  it('extrae la clave de una URL propia', () => {
    expect(keyFromPublicUrl(base, `${base}/products/abc/1.webp`)).toBe('products/abc/1.webp');
  });

  it('ignora URLs de otros dominios', () => {
    expect(keyFromPublicUrl(base, 'https://otro.com/products/1.webp')).toBeNull();
  });

  it('rechaza rutas con ..', () => {
    expect(keyFromPublicUrl(base, `${base}/../secreto`)).toBeNull();
  });
});
