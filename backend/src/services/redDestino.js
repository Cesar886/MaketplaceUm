// Defensa contra SSRF para las peticiones salientes que hace el backend.
//
// La comprobación del link de un negocio es la única parte del sistema donde
// un dato controlado por el usuario decide a qué dirección se conecta el
// servidor. La whitelist de dominios no basta por sí sola: varios de los
// hosts permitidos son acortadores (maps.app.goo.gl) que pueden redirigir a
// cualquier parte, incluyendo 127.0.0.1 o el endpoint de metadata de la nube
// (169.254.169.254). Aunque el endpoint solo devuelve "responde / no
// responde", ese booleano alcanza para mapear qué servicios internos existen.
//
// Por eso cada salto de la cadena de redirecciones se resuelve por DNS y se
// rechaza si apunta a una dirección no pública.

const dns = require('dns').promises;
const net = require('net');

function aBytesIPv4(ip) {
  const partes = ip.split('.');
  if (partes.length !== 4) return null;
  const bytes = partes.map(Number);
  return bytes.every(b => Number.isInteger(b) && b >= 0 && b <= 255)
    ? bytes
    : null;
}

function esIPv4Privada(ip) {
  const b = aBytesIPv4(ip);
  if (!b) return false;
  const [a, segundo] = b;

  if (a === 0) return true; // 0.0.0.0/8 "esta red"
  if (a === 10) return true; // RFC1918
  if (a === 127) return true; // loopback
  if (a === 169 && segundo === 254) return true; // link-local (metadata cloud)
  if (a === 172 && segundo >= 16 && segundo <= 31) return true; // RFC1918
  if (a === 192 && segundo === 168) return true; // RFC1918
  if (a === 100 && segundo >= 64 && segundo <= 127) return true; // CGNAT
  if (a === 192 && segundo === 0) return true; // IETF protocol assignments
  if (a === 198 && (segundo === 18 || segundo === 19)) return true; // benchmarking
  if (a >= 224) return true; // multicast (224/4) y reservado (240/4)
  return false;
}

/**
 * ¿La dirección apunta a algo que no es internet público?
 * Acepta IPv4, IPv6 y IPv4 mapeada en IPv6 (::ffff:127.0.0.1).
 */
function esIpPrivada(ip) {
  if (typeof ip !== 'string' || !ip) return true;

  const version = net.isIP(ip);
  if (version === 4) return esIPv4Privada(ip);
  if (version !== 6) return true; // no es una IP: se trata como no permitida

  const normalizada = ip.toLowerCase().split('%')[0]; // quita zona (fe80::1%eth0)

  // Una IPv4 envuelta en IPv6 se evalúa como IPv4: ::ffff:127.0.0.1 es
  // loopback, aunque escrito así parezca otra cosa.
  const mapeada = normalizada.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  if (mapeada) return esIPv4Privada(mapeada[1]);

  if (normalizada === '::1' || normalizada === '::') return true;
  if (/^f[cd]/.test(normalizada)) return true; // ULA fc00::/7
  if (/^fe[89ab]/.test(normalizada)) return true; // link-local fe80::/10
  if (/^ff/.test(normalizada)) return true; // multicast
  return false;
}

/**
 * Resuelve el hostname y exige que TODAS sus direcciones sean públicas: si
 * una sola apunta hacia dentro, el host se rechaza (un atacante no elige
 * cuál usa el cliente).
 *
 * @returns {Promise<boolean>}
 */
async function esDestinoPermitido(hostname) {
  if (!hostname) return false;

  // Un host que ya es una IP literal no necesita DNS.
  if (net.isIP(hostname)) return !esIpPrivada(hostname);

  let direcciones;
  try {
    direcciones = await dns.lookup(hostname, { all: true });
  } catch {
    // No resuelve: no hay nada que verificar y tampoco a dónde conectarse.
    return false;
  }
  if (!direcciones.length) return false;
  return direcciones.every(d => !esIpPrivada(d.address));
}

module.exports = { esIpPrivada, esDestinoPermitido };
