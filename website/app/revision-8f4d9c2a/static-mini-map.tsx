import styles from './revision.module.css';

type Props = {
  lat: number;
  lng: number;
  source: 'request' | 'profile';
};

const zoom = 15;
const tileSize = 256;
const maxLatitude = 85.05112878;

export default function StaticMiniMap({ lat, lng, source }: Props) {
  const safeLat = Math.max(-maxLatitude, Math.min(maxLatitude, lat));
  const normalizedLng = ((lng + 180) % 360 + 360) % 360 - 180;
  const tileCount = 2 ** zoom;
  const latRad = safeLat * Math.PI / 180;
  const worldX = (normalizedLng + 180) / 360 * tileCount;
  const worldY = (
    1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI
  ) / 2 * tileCount;
  const centerX = Math.floor(worldX);
  const centerY = Math.floor(worldY);
  const fractionX = worldX - centerX;
  const fractionY = worldY - centerY;
  const tiles = [];

  for (let offsetY = -1; offsetY <= 1; offsetY += 1) {
    for (let offsetX = -2; offsetX <= 2; offsetX += 1) {
      const x = ((centerX + offsetX) % tileCount + tileCount) % tileCount;
      const y = Math.max(0, Math.min(tileCount - 1, centerY + offsetY));
      tiles.push({ x, y, offsetX, offsetY });
    }
  }

  const mapsUrl = `https://www.google.com/maps/search/?api=1&query=${lat},${lng}`;

  return (
    <div className={styles.miniMapBlock}>
      <div
        aria-label={`Mapa de la ubicación ${lat.toFixed(6)}, ${lng.toFixed(6)}`}
        className={styles.mapViewport}
        role="img"
      >
        {tiles.map(tile => (
          <img
            alt=""
            className={styles.mapTile}
            key={`${tile.x}-${tile.y}`}
            src={`https://tile.openstreetmap.org/${zoom}/${tile.x}/${tile.y}.png`}
            style={{
              left: `calc(50% + ${(tile.offsetX - fractionX) * tileSize}px)`,
              top: `calc(50% + ${(tile.offsetY - fractionY) * tileSize}px)`,
            }}
          />
        ))}
        <svg
          aria-hidden="true"
          className={styles.mapPin}
          viewBox="0 0 32 40"
        >
          <path
            d="M16 1C7.7 1 1 7.7 1 16c0 10.4 15 23 15 23s15-12.6 15-23C31 7.7 24.3 1 16 1Z"
            fill="#d8382f"
            stroke="#fff"
            strokeWidth="2"
          />
          <circle cx="16" cy="16" fill="#fff" r="5" />
        </svg>
        <a
          className={styles.mapAttribution}
          href="https://www.openstreetmap.org/copyright"
          rel="noreferrer"
          target="_blank"
        >
          © OpenStreetMap
        </a>
      </div>
      <div className={styles.mapFooter}>
        <div>
          <strong>{lat.toFixed(6)}, {lng.toFixed(6)}</strong>
          <span>
            {source === 'request'
              ? 'Coordenadas enviadas en esta solicitud'
              : 'Coordenadas guardadas en el perfil'}
          </span>
        </div>
        <a href={mapsUrl} rel="noreferrer" target="_blank">
          Abrir en Google Maps
        </a>
      </div>
    </div>
  );
}
