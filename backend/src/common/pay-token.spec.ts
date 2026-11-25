import { signPayload, signReceipt, signTablePay, verifyPayload, verifyReceipt, verifyTablePay } from './pay-token';

const SECRET = 'x'.repeat(40);

describe('enlace de pago de la mesa', () => {
  it('se verifica con la misma clave', () => {
    const token = signTablePay('clx1abc234def567ghi890', SECRET);
    expect(verifyTablePay(token, SECRET)).toBe('clx1abc234def567ghi890');
  });

  it('no sirve con otra clave ni alterado', () => {
    const token = signTablePay('clx1abc234def567ghi890', SECRET);
    expect(verifyTablePay(token, 'y'.repeat(40))).toBeNull();
    const [id] = token.split('.');
    const other = Buffer.from('clx1abc234def567ghi891').toString('base64url');
    expect(verifyTablePay(`${other}.${token.split('.')[1]}`, SECRET)).toBeNull();
    expect(verifyTablePay(`${id}.AAAAAAAAAAAAAAAAAAAAAA`, SECRET)).toBeNull();
    expect(verifyTablePay('basura', SECRET)).toBeNull();
    expect(verifyTablePay(`${token}.extra`, SECRET)).toBeNull();
  });

  it('un enlace de pago no sirve como recibo (ni al revés)', () => {
    const id = 'clx1abc234def567ghi890';
    expect(verifyReceipt(signReceipt(id, SECRET), SECRET)).toBe(id);
    expect(verifyReceipt(signTablePay(id, SECRET), SECRET)).toBeNull();
    expect(verifyTablePay(signReceipt(id, SECRET), SECRET)).toBeNull();
  });

  it('un enlace de descarga firmado no se puede alterar', () => {
    const token = signPayload('report-export:v1', '2026-11-01|2026-11-24|9999999999999', SECRET);
    expect(verifyPayload('report-export:v1', token, SECRET)).toBe('2026-11-01|2026-11-24|9999999999999');
    const forged = `${Buffer.from('2020-01-01|2026-11-24|9999999999999').toString('base64url')}.${token.split('.')[1]}`;
    expect(verifyPayload('report-export:v1', forged, SECRET)).toBeNull();
    expect(verifyPayload('otra-cosa', token, SECRET)).toBeNull();
  });
});
