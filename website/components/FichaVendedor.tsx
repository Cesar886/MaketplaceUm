import { urlFoto } from '@/lib/api';
import { subtituloRol } from '@/lib/formato';
import type { VendedorPublico } from '@/lib/tipos';

/**
 * Azul de verificación estilo Meta/Instagram — mismo valor que
 * `AppColors.verifiedBlue` en `lib/app_theme.dart`, para que la insignia se
 * vea igual en la web y en la app.
 */
const AZUL_VERIFICADO = '#3897F0';

/**
 * Quién publica: avatar (foto real si existe, si no iniciales), nombre y rol.
 *
 * Es el mismo bloque para un producto y para una búsqueda — cambia el
 * sustantivo (vendedor / quien busca), no los datos ni su disposición — así
 * que vive aparte para que las dos vistas no se desincronicen.
 *
 * Tampoco hay enlace al perfil, porque no existe una página pública de
 * perfil y no debe existir sin decidirlo explícitamente.
 */
export default function FichaVendedor({
  vendedor,
}: {
  vendedor: VendedorPublico;
}) {
  const rol = subtituloRol(vendedor);

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
      {vendedor.avatarUrl ? (
        <img
          src={urlFoto(vendedor.avatarUrl)}
          alt=""
          aria-hidden="true"
          style={{
            width: 44,
            height: 44,
            flexShrink: 0,
            borderRadius: 999,
            objectFit: 'cover',
          }}
        />
      ) : (
        <div
          aria-hidden="true"
          style={{
            width: 44,
            height: 44,
            flexShrink: 0,
            borderRadius: 999,
            display: 'grid',
            placeItems: 'center',
            background: 'color-mix(in srgb, var(--primary) 12%, transparent)',
            color: 'var(--primary)',
            fontWeight: 700,
            fontSize: 15,
          }}
        >
          {vendedor.iniciales}
        </div>
      )}
      <div style={{ minWidth: 0 }}>
        <p
          style={{
            margin: 0,
            display: 'flex',
            alignItems: 'center',
            gap: 5,
            fontWeight: 700,
            fontSize: 16,
          }}
        >
          {vendedor.nombre}
          {vendedor.verificado && (
            <svg
              width="16"
              height="16"
              viewBox="0 0 24 24"
              fill="none"
              aria-label="Cuenta verificada"
              style={{ flexShrink: 0 }}
            >
              <circle cx="12" cy="12" r="12" fill={AZUL_VERIFICADO} />
              <path
                d="M7 12.5l3.2 3.2L17 9"
                stroke="#fff"
                strokeWidth="2.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          )}
        </p>
        {/* Sin rol comprobado no se pinta la línea, igual que en la app. */}
        {rol && <p style={{ margin: 0, fontSize: 13, color: 'var(--muted)' }}>{rol}</p>}
      </div>
    </div>
  );
}
