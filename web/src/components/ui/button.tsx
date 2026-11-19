type Props = {
  children: React.ReactNode;
  onClick?: () => void;
  variant?: 'primary' | 'ghost';
};

export default function Button({ children, onClick, variant = 'primary' }: Props) {
  const className =
    variant === 'primary'
      ? 'btn-primary'
      : 'btn-ghost';

  return (
    <button className={className} onClick={onClick}>
      {children}
    </button>
  );
}