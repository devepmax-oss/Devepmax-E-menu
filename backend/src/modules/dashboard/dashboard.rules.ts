/** Reglas puras del tablero del dueño: alertas a partir de los números del día. */

export type AlertLevel = 'danger' | 'warning' | 'info';

export interface DashboardAlert {
  id: string;
  level: AlertLevel;
  title: string;
  detail: string;
  /** Pantalla de la app del personal donde se atiende. */
  action: string | null;
}

export interface AlertInput {
  net: number;
  lastWeekSoFar: number;
  laborCost: number;
  foodCost: number | null;
  lowStock: string[];
  lateTickets: number;
  oldestTicketMinutes: number;
  orders: number;
  cancellations: number;
  manualDiscounts: number;
  manualDiscountAmount: number;
  gross: number;
  missingOut: number;
  onlinePaused: boolean;
}

/** Límites de las alertas (se pueden volver ajustes más adelante). */
export const THRESHOLDS = {
  /** Ventas por debajo de este % de la semana pasada a esta hora. */
  salesLowRatio: 0.7,
  /** Desde cuánto vendido la semana pasada a esta hora tiene sentido comparar. */
  salesCompareMin: 100,
  /** Costo de personal y food cost: % de las ventas. */
  laborPercent: 35,
  foodPercent: 35,
  /** Desde cuánto vendido hoy se miran los porcentajes. */
  percentMinSales: 200,
  kitchenLateMinutes: 25,
  cancellationsMin: 3,
  cancellationsRatio: 0.1,
  discountsMin: 3,
  discountsRatio: 0.1,
};

const money = (v: number) => `$${v.toFixed(2)}`;
const pct = (v: number) => `${Math.round(v)} %`;

export function buildAlerts(i: AlertInput): DashboardAlert[] {
  const t = THRESHOLDS;
  const alerts: DashboardAlert[] = [];
  if (i.lateTickets > 0) {
    alerts.push({
      id: 'kitchen_late',
      level: 'danger',
      title: i.lateTickets === 1 ? '1 ticket atrasado en cocina' : `${i.lateTickets} tickets atrasados en cocina`,
      detail: `Más de ${t.kitchenLateMinutes} min sin estar listos; el más viejo lleva ${i.oldestTicketMinutes} min.`,
      action: '/orders',
    });
  }
  if (i.lastWeekSoFar >= t.salesCompareMin && i.net < i.lastWeekSoFar * t.salesLowRatio) {
    const drop = (1 - i.net / i.lastWeekSoFar) * 100;
    alerts.push({
      id: 'sales_low',
      level: 'warning',
      title: `Ventas ${pct(drop)} abajo de la semana pasada`,
      detail: `Hoy ${money(i.net)} contra ${money(i.lastWeekSoFar)} el mismo día de la semana pasada a esta hora.`,
      action: '/reports',
    });
  }
  if (i.net >= t.percentMinSales && i.laborCost > 0 && (i.laborCost / i.net) * 100 > t.laborPercent) {
    alerts.push({
      id: 'labor_high',
      level: 'warning',
      title: `Personal: ${pct((i.laborCost / i.net) * 100)} de las ventas`,
      detail: `${money(i.laborCost)} en sueldos hoy para ${money(i.net)} vendidos (lo sano es hasta ${t.laborPercent} %).`,
      action: '/attendance',
    });
  }
  if (i.foodCost !== null && i.net >= t.percentMinSales && (i.foodCost / i.net) * 100 > t.foodPercent) {
    alerts.push({
      id: 'food_cost_high',
      level: 'warning',
      title: `Food cost: ${pct((i.foodCost / i.net) * 100)} de las ventas`,
      detail: `${money(i.foodCost)} en ingredientes hoy (lo sano es hasta ${t.foodPercent} %). Revisa recetas y precios.`,
      action: '/inventory',
    });
  }
  if (i.lowStock.length > 0) {
    const names = i.lowStock.slice(0, 4).join(', ') + (i.lowStock.length > 4 ? ` y ${i.lowStock.length - 4} más` : '');
    alerts.push({
      id: 'low_stock',
      level: 'warning',
      title: i.lowStock.length === 1 ? '1 ingrediente bajo el mínimo' : `${i.lowStock.length} ingredientes bajo el mínimo`,
      detail: names,
      action: '/inventory',
    });
  }
  if (i.cancellations >= t.cancellationsMin && i.orders > 0 && i.cancellations / i.orders >= t.cancellationsRatio) {
    alerts.push({
      id: 'cancellations',
      level: 'warning',
      title: `${i.cancellations} órdenes canceladas hoy`,
      detail: `Son el ${pct((i.cancellations / i.orders) * 100)} de las órdenes del día.`,
      action: '/reports',
    });
  }
  if (i.manualDiscounts >= t.discountsMin && i.gross > 0 && i.manualDiscountAmount / i.gross >= t.discountsRatio) {
    alerts.push({
      id: 'discounts',
      level: 'warning',
      title: `Descuentos: ${money(i.manualDiscountAmount)} hoy`,
      detail: `${i.manualDiscounts} descuentos manuales, el ${pct((i.manualDiscountAmount / i.gross) * 100)} de lo vendido.`,
      action: '/reports',
    });
  }
  if (i.missingOut > 0) {
    alerts.push({
      id: 'missing_out',
      level: 'info',
      title: i.missingOut === 1 ? '1 jornada sin salida marcada' : `${i.missingOut} jornadas sin salida marcada`,
      detail: 'Corrígelas para que la nómina salga bien.',
      action: '/attendance',
    });
  }
  if (i.onlinePaused) {
    alerts.push({
      id: 'online_paused',
      level: 'info',
      title: 'Los pedidos online están en pausa',
      detail: 'La web no recibe pedidos hasta que la reactives en Ajustes.',
      action: '/settings',
    });
  }
  return alerts;
}

/** Cambio en % contra antes (null si antes no hubo nada). */
export function change(now: number, before: number): number | null {
  if (Math.abs(before) < 0.005) return null;
  return Math.round(((now - before) / Math.abs(before)) * 1000) / 10;
}
