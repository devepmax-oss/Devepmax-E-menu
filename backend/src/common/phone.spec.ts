import { maskTarget, toE164 } from './phone';

describe('teléfonos y avisos de código', () => {
  it('normaliza teléfonos de EE. UU.', () => {
    expect(toE164('(305) 555-0123')).toBe('+13055550123');
    expect(toE164('1 305 555 0123')).toBe('+13055550123');
    expect(toE164('12345')).toBeNull();
  });

  it('no muestra el teléfono ni el email completos', () => {
    expect(maskTarget('+13055550123')).toBe('•••-•••-0123');
    expect(maskTarget('maria@example.com')).toBe('ma•••@example.com');
  });
});
