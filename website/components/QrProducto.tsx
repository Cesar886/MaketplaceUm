import QRCode from 'react-qr-code';

/**
 * QR de la URL del producto, para escritorio: en una pantalla grande no hay
 * tienda a la que enviar al usuario, así que el puente es su propio teléfono.
 *
 * Se renderiza como SVG (no canvas), así que funciona en un Server Component
 * y sale nítido en cualquier densidad de pantalla.
 */
export default function QrProducto({ url }: { url: string }) {
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 20,
        padding: 20,
        border: '1px solid var(--border)',
        borderRadius: 'var(--radio)',
        background: 'var(--surface)',
      }}
    >
      <div style={{ background: '#fff', padding: 8, borderRadius: 8, flexShrink: 0 }}>
        <QRCode
          value={url}
          size={116}
          // Mismo azul de marca que usa el QR dentro de la app
          // (`qr_display_screen.dart`).
          fgColor="#2b4150"
          bgColor="#ffffff"
        />
      </div>
      <div>
        <p style={{ margin: 0, fontWeight: 700, fontSize: 16 }}>
          Escanea con tu celular
        </p>
        <p style={{ margin: '4px 0 0', color: 'var(--muted)', fontSize: 14 }}>
          Abre este producto en Marketplace UM y escríbele al vendedor.
        </p>
      </div>
    </div>
  );
}
