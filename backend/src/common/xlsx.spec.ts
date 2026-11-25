import { inflateRawSync } from 'node:zlib';
import { buildXlsx, columnName, crc32 } from './xlsx';

/** Lee las entradas del zip (lo que haría Excel al abrirlo). */
function unzip(buffer: Buffer): Map<string, string> {
  const files = new Map<string, string>();
  let i = 0;
  while (buffer.readUInt32LE(i) === 0x04034b50) {
    const method = buffer.readUInt16LE(i + 8);
    const crc = buffer.readUInt32LE(i + 14);
    const size = buffer.readUInt32LE(i + 18);
    const nameLength = buffer.readUInt16LE(i + 26);
    const name = buffer.subarray(i + 30, i + 30 + nameLength).toString('utf8');
    const raw = buffer.subarray(i + 30 + nameLength, i + 30 + nameLength + size);
    const data = method === 8 ? inflateRawSync(raw) : raw;
    expect(crc32(data)).toBe(crc);
    files.set(name, data.toString('utf8'));
    i += 30 + nameLength + size;
  }
  expect(buffer.readUInt32LE(buffer.length - 22)).toBe(0x06054b50);
  return files;
}

describe('exportar a Excel', () => {
  it('calcula el CRC como el estándar', () => {
    expect(crc32(Buffer.from('123456789'))).toBe(0xcbf43926);
  });

  it('nombra las columnas como Excel', () => {
    expect([0, 25, 26, 27, 51, 52, 701, 702].map(columnName)).toEqual(['A', 'Z', 'AA', 'AB', 'AZ', 'BA', 'ZZ', 'AAA']);
  });

  it('arma un libro con varias hojas, números, dinero y texto con acentos', () => {
    const xlsx = buildXlsx([
      { name: 'Resumen', rows: [['Concepto', 'Monto'], ['Ventas netas', { money: 1234.5 }], ['Órdenes', 42]], widths: [24, 14] },
      { name: 'Productos/Categorías?', rows: [['Producto', 'Cantidad'], ['Pollo & papas <grande>', 3]] },
    ]);
    expect(xlsx.subarray(0, 2).toString()).toBe('PK');
    const files = unzip(xlsx);
    expect([...files.keys()]).toEqual(
      expect.arrayContaining(['[Content_Types].xml', 'xl/workbook.xml', 'xl/styles.xml', 'xl/worksheets/sheet1.xml', 'xl/worksheets/sheet2.xml']),
    );
    expect(files.get('xl/workbook.xml')).toContain('name="Resumen"');
    expect(files.get('xl/workbook.xml')).toContain('name="Productos Categorías"');
    const sheet1 = files.get('xl/worksheets/sheet1.xml')!;
    expect(sheet1).toContain('<c r="B2" s="2"><v>1234.5</v></c>');
    expect(sheet1).toContain('<c r="B3"><v>42</v></c>');
    expect(sheet1).toContain('<c r="A1" t="inlineStr" s="1">');
    expect(files.get('xl/worksheets/sheet2.xml')).toContain('Pollo &amp; papas &lt;grande&gt;');
  });
});
