import { Category, Product } from '@/lib/types';
import ProductCard from './product-card';

type CategorySectionProps = {
  category: Category;
};

export default function CategorySection({ category }: CategorySectionProps) {
  if (!category.products?.length) {
    return null;
  }

  return (
    <section
      id={`category-${category.id}`}
      className="scroll-mt-28 space-y-5"
    >
      <div className="flex items-end justify-between gap-4">
        <div>
          <h2 className="text-2xl font-extrabold tracking-tight text-neutral-950 transition-colors dark:text-neutral-100 sm:text-3xl">
            {category.name}
          </h2>
          <p className="mt-1 text-sm text-neutral-500 transition-colors dark:text-neutral-400">
            {category.products.length} producto
            {category.products.length !== 1 ? 's' : ''}
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {category.products.map((product: Product) => (
          <ProductCard
            key={product.id}
            product={product}
          />
        ))}
      </div>
    </section>
  );
}