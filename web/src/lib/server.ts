import { cache } from 'react';
import { api } from './api';

/** Una sola consulta por visita aunque la pidan el layout y la página. */
export const getConfig = cache(async () => {
  try {
    return await api.config();
  } catch {
    return null;
  }
});

export async function safe<T>(promise: Promise<T>): Promise<T | null> {
  try {
    return await promise;
  } catch {
    return null;
  }
}
