import { getMenu } from '@/lib/api';
import MenuHomeClient from '@/app/menu/menu-home-client';

export default async function MenuPage() {
  const categories = await getMenu();
  return <MenuHomeClient categories={categories} />;
}