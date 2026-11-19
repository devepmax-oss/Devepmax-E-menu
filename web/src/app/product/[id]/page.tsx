import { getProduct } from '@/lib/api';
import ProductDetailClient from '@/app/menu/product-detail-client';

type Props = {
  params: Promise<{
    id: string;
  }>;
};

export default async function ProductDetailPage({ params }: Props) {
  const { id } = await params;
  const product = await getProduct(id);

  return <ProductDetailClient product={product} />;
}