import { toE164 } from './receipts.service';

describe('teléfono para el SMS del recibo', () => {
  it('acepta números de EE. UU. escritos de cualquier forma', () => {
    expect(toE164('(305) 555-1234')).toBe('+13055551234');
    expect(toE164('305.555.1234')).toBe('+13055551234');
    expect(toE164('1 305 555 1234')).toBe('+13055551234');
    expect(toE164('+1 305 555 1234')).toBe('+13055551234');
  });

  it('acepta otros países con +código', () => {
    expect(toE164('+52 55 1234 5678')).toBe('+525512345678');
  });

  it('rechaza números incompletos', () => {
    expect(toE164('555-1234')).toBeNull();
    expect(toE164('+12')).toBeNull();
  });
});
