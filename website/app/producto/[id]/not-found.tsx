import Link from 'next/link';

export default function NoEncontrado() {
  return (
    <main
      className="contenedor"
      style={{ padding: '80px 18px 120px', textAlign: 'center' }}
    >
      <h1 style={{ fontSize: 24 }}>Esta publicación ya no está disponible</h1>
      <p style={{ color: 'var(--muted)', marginTop: 10, fontSize: 15 }}>
        Puede que el vendedor la haya eliminado o que el link esté incompleto.
      </p>
      <div style={{ marginTop: 26 }}>
        <Link className="boton-principal" href="/">
          Conocer Marketplace UM
        </Link>
      </div>
    </main>
  );
}
