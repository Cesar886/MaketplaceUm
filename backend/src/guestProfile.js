// Identidad publica minima para las sesiones de invitado.
//
// Los invitados ya tienen un id estable y firmado por el servidor para el
// chat (`anon_<uuid>`), pero no tienen una fila en `sellers`. Centralizar la
// representacion aqui evita que la bandeja y el endpoint de perfil inventen
// objetos distintos para la misma persona.

// Se acepta cualquier UUID hexadecimal, no solo UUID v4. Las sesiones
// actuales son v4, pero antes de que el servidor emitiera la identidad la
// app generaba UUID con el mismo formato sin fijar los bits de version. Sus
// conversaciones siguen siendo validas y tambien deben abrir perfil.
const GUEST_ID_PATTERN = /^anon_[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

function isGuestId(id) {
  return typeof id === 'string' && GUEST_ID_PATTERN.test(id);
}

function guestPublicProfile(id) {
  if (!isGuestId(id)) return null;
  return {
    id,
    name: 'Usuario invitado',
    avatarInitials: 'UI',
    major: 'Invitado',
    isGuest: true,
    isBusiness: false,
    logoUrl: null,
    phone: null,
    rating: 0,
    reviews: 0,
    profileViews: 0,
    verified: false,
    socioFundador: false,
    tipoCuenta: 'particular',
    carrera: null,
    tipoVerificacion: null,
    businessDescription: null,
    businessCategory: null,
    businessHours: {},
    locationLat: null,
    locationLng: null,
    paymentMethods: [],
    colorAcento: null,
    productoFijadoId: null,
    respondeRapido: false,
    respuestaInstantanea: false,
    vendedorConfiable: false,
    esVendedorNuevo: false,
    leyendaMercadito: false,
    vendedorDeOro: false,
    ratingPerfecto: false,
    cienCincoEstrellas: false,
    siempreResponde: false,
    aniversarioAnios: 0,
    rachaSemanas: 0,
    enigmaPosicion: null,
    facebookUrl: null,
    instagramUrl: null,
    whatsappNumber: null,
    tiktokUrl: null,
    twitterUrl: null,
  };
}

module.exports = { isGuestId, guestPublicProfile };
