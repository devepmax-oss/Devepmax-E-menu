import { signTablePay, verifyTablePay } from './pay-token';

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
});
