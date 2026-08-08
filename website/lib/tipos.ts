/** Espejo de `aVistaPublica` en `backend/src/routes/public.js`. */

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
