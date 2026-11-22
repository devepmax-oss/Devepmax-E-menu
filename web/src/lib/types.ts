/** Tipos de la API pública del backend (/api/v1). Los montos llegan como texto ("14.50"). */

export type Money = string;
export type FulfillmentType = 'PICKUP' | 'DELIVERY';
export type ThemeMode = 'dark' | 'light';

export interface OpeningWindow {
  dayOfWeek: number;
  opensAt: string;
  closesAt: string;
}

export interface OnlineConfig {
  name: string;
  logoUrl: string | null;
  primaryColor: string;
  accentColor: string;
  themeMode: ThemeMode;
  fontPair: string;
  phone: string | null;
  whatsapp: string | null;
  email: string | null;
  address: {
    line: string | null;
    city: string | null;
    state: string | null;
    zipCode: string | null;
    lat: Money | null;
    lng: Money | null;
  };
  socialLinks: Record<string, string> | null;
  timezone: string;
  currency: string;
  locales: string[];
  channels: { dineIn: boolean; pickup: boolean; delivery: boolean; onlineOrderingPaused: boolean };
  prepTimeMinutes: number;
  tipPresets: number[];
  maintenanceMode: boolean;
  openingHours: OpeningWindow[];
  isOpenNow: boolean;
  delivery: { fee: Money; minOrder: Money; etaMinutes: number };
  payments: { card: boolean; payAtPickup: boolean; publishableKey: string | null };
}

export interface MenuOption {
  id: string;
  name: string;
  priceAdjustment: Money;
  isDefault: boolean;
  isAvailable: boolean;
}

export interface MenuModifierGroup {
  id: string;
  name: string;
  selectionType: 'SINGLE' | 'MULTIPLE';
  minSelect: number;
  maxSelect: number | null;
  options: MenuOption[];
}

export interface MenuProduct {
  id: string;
  name: string;
  description: string | null;
  price: Money;
  imageUrl: string | null;
  isAvailable: boolean;
  allergens: string[];
  prepTimeMinutes: number | null;
  modifierGroups: MenuModifierGroup[];
}

export interface MenuCategory {
  id: string;
  name: string;
  imageUrl: string | null;
  products: MenuProduct[];
}

export interface PublicMenu {
  channel: string;
  categories: MenuCategory[];
}

export type PromotionType = 'PERCENT_OFF' | 'AMOUNT_OFF' | 'BUY_X_GET_Y' | 'COMBO_PRICE';

export interface PublicPromotion {
  id: string;
  name: string;
  description: string | null;
  type: PromotionType;
  value: Money | null;
  buyQuantity: number | null;
  getQuantity: number | null;
  comboPrice: Money | null;
  endsAt: string | null;
  productIds: string[];
  categoryIds: string[];
}

export interface OrderLineInput {
  productId: string;
  quantity: number;
  optionIds: string[];
  notes?: string;
}

export interface Totals {
  subtotal: Money;
  discountTotal: Money;
  taxTotal: Money;
  deliveryFee: Money;
  tipTotal: Money;
  total: Money;
}

export interface Quote {
  lines: {
    productId: string;
    name: string;
    quantity: number;
    unitPrice: Money;
    modifiersTotal: Money;
    lineTotal: Money;
    discount: Money;
    modifiers: { group: string; option: string }[];
  }[];
  promotions: { promotionId: string; name: string; amount: Money }[];
  totals: Totals;
  minOrder: Money;
  meetsMinimum: boolean;
}

export type PublicStage =
  | 'awaiting_payment'
  | 'received'
  | 'preparing'
  | 'ready'
  | 'on_the_way'
  | 'completed'
  | 'cancelled';

export interface PublicOrder {
  number: number;
  publicCode: string;
  fulfillmentType: FulfillmentType | 'DINE_IN' | 'TAKEOUT';
  status: string;
  stage: PublicStage;
  customerFirstName: string | null;
  createdAt: string;
  placedAt: string | null;
  estimatedReadyAt: string | null;
  readyAt: string | null;
  completedAt: string | null;
  cancelledAt: string | null;
  updatedAt: string;
  items: {
    name: string;
    quantity: number;
    lineTotal: Money;
    discount: Money;
    modifiers: { group: string; option: string }[];
  }[];
  promotions: { name: string; amount: Money }[];
  totals: Totals & { amountPaid: Money; paid: boolean };
}

export interface CreatedOrder {
  order: PublicOrder;
  payment: { clientSecret: string; publishableKey: string | null } | null;
}
