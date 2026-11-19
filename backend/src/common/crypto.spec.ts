import { generatePairingCode, generateToken, hashPassword, hashPin, verifyPassword } from './crypto';

describe('crypto', () => {
  it('verifica la contraseña correcta y rechaza la incorrecta', async () => {
    const stored = await hashPassword('clave-segura-123');
    expect(stored.startsWith('scrypt$')).toBe(true);
    await expect(verifyPassword('clave-segura-123', stored)).resolves.toBe(true);
    await expect(verifyPassword('otra-clave', stored)).resolves.toBe(false);
  });

  it('usa una sal distinta en cada hash', async () => {
    expect(await hashPassword('igual')).not.toEqual(await hashPassword('igual'));
  });

  it('rechaza formatos de hash desconocidos', async () => {
    await expect(verifyPassword('x', 'md5$abc')).resolves.toBe(false);
  });

  it('el hash del PIN depende del pepper y es determinístico', () => {
    expect(hashPin('1234', 'a'.repeat(32))).toEqual(hashPin('1234', 'a'.repeat(32)));
    expect(hashPin('1234', 'a'.repeat(32))).not.toEqual(hashPin('1234', 'b'.repeat(32)));
  });

  it('genera códigos de 6 dígitos y tokens sin puntos', () => {
    for (let i = 0; i < 50; i++) expect(generatePairingCode()).toMatch(/^\d{6}$/);
    expect(generateToken()).not.toContain('.');
  });
});
