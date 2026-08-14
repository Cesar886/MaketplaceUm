/**
 * Espejo de `aVistaPublica` y `aVistaPublicaBusqueda` en
 * `backend/src/routes/public.js`.
 *
 * `/producto/:id` sirve las dos cosas que la app deja compartir: un producto
 * en venta y una publicación "se busca". El campo `tipo` es el discriminante;
 * TypeScript no deja leer `precio` o `fotos` sin haberlo comprobado antes.
 */

export type EstadoProducto =
  | 'available'
  | 'sold_out'
  | 'available_other_day'
  | 'closed'
  | 'reserved'
  | 'negotiating'
  | 'sold'
  | 'paused';

export interface VendedorPublico {
  nombre: string;
  iniciales: string;
  esNegocio: boolean;
  verificado: boolean;
  tipoCuenta: string | null;
  carrera: string | null;
  tipoVerificacion: string | null;
}

export interface ProductoPublico {
  tipo: 'producto';
  id: string;
  titulo: string;
  descripcion: string;
  precio: number;
  precioAnterior: number | null;
  etiquetaDescuento: string | null;
  categoria: { id: string; nombre: string } | null;
  /** Rutas relativas del backend ('/uploads/x.webp'). Ver `urlFoto`. */
  fotos: string[];
  estado: EstadoProducto;
  estadoDetalle: { next_available_day?: string | null; opens_at?: string } | null;
  disponible: boolean;
  publicadoHace: string | null;
  ubicacion: { lat: number; lng: number } | null;
  vendedor: VendedorPublico | null;
}

export interface BusquedaPublica {
  tipo: 'busqueda';
  id: string;
  titulo: string;
  descripcion: string;
  /** Rango de lo que se está dispuesto a pagar. Cualquiera de los dos extremos
   *  puede faltar: se pide "hasta X" o "desde Y", o nada. */
  precioMin: number | null;
  precioMax: number | null;
  /** Cambia el verbo de la página: comprar un producto, contratar un servicio. */
  busca: 'producto' | 'servicio';
  categoria: { id: string; nombre: string } | null;
  /** Una búsqueda resuelta sigue siendo visible, pero se marca como cerrada. */
  abierta: boolean;
  /** ISO 8601, a diferencia de `publicadoHace` que ya viene formateado. */
  publicadoEn: string | null;
  ubicacion: { lat: number; lng: number } | null;
  vendedor: VendedorPublico | null;
}

export type PublicacionPublica = ProductoPublico | BusquedaPublica;
