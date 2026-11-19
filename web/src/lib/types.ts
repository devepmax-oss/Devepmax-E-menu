export type ModifierOption = {
  id: string;
  name: string;
  priceAdjustment: string;
  isActive: boolean;
};

export type ModifierGroup = {
  id: string;
  name: string;
  selectionType: 'single' | 'multiple';
  minSelect: number;
  maxSelect: number;
  isRequired: boolean;
  isActive: boolean;
  options: ModifierOption[];
};

export type Product = {
  id: string;
  name: string;
  description: string | null;
  price: string;
  imageUrl: string | null;
  isActive: boolean;
  modifierGroups: ModifierGroup[];
};

export type ProductDetail = Product & {
  category: {
    id: string;
    name: string;
    isActive: boolean;
  };
};

export type Category = {
  id: string;
  name: string;
  isActive: boolean;
  products: Product[];
};