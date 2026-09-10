import type { Metadata } from 'next';

import PalabrasDinamicas from '@/components/PalabrasDinamicas';
import { obtenerProductosParaPortada, SITE_URL, urlFoto } from '@/lib/api';

export const metadata: Metadata = {
  title: 'Marketplace UM — Todo lo que buscas, dentro de tu comunidad',
  description:
    'Descubre, compra y vende libros, tecnología, comida y más dentro de la comunidad de la Universidad de Montemorelos.',
  alternates: { canonical: SITE_URL },
};

const categorias = ['Libros', 'Tecnología', 'Comida', 'Servicios', 'Apuntes', 'Ropa'];

function precio(valor: number) {
  return new Intl.NumberFormat('es-MX', {
    style: 'currency', currency: 'MXN', maximumFractionDigits: 0,
  }).format(valor);
}

export default async function Inicio() {
  const productos = await obtenerProductosParaPortada(3);

  return (
    <main className="landing">
      <nav className="landing-nav" aria-label="Navegación principal">
        <a className="landing-marca" href="#inicio" aria-label="Marketplace UM, inicio">
          <img src="/icon.png" alt="" width="42" height="42" />
          <span>Marketplace UM</span>
        </a>
        <div className="landing-nav-derecha">
          <span className="landing-en-vivo"><i /> Comunidad UM</span>
          <a className="landing-nav-link" href="#vitrina">Explorar</a>
        </div>
      </nav>

      <section className="landing-hero" id="inicio">
        <div className="landing-brillo landing-brillo--uno" />
        <div className="landing-brillo landing-brillo--dos" />
        <div className="landing-hero-copy">
          <p className="landing-eyebrow"><span>✦</span> El mercado de nuestra comunidad</p>
          <h1>Encuentra <PalabrasDinamicas /><br />sin salir de la UM.</h1>
          <p className="landing-bajada">
            Compra, vende y descubre lo que se mueve cerca de ti. Personas reales,
            negocios locales y oportunidades que nacen dentro de la comunidad.
          </p>
          <div className="landing-acciones">
            <a className="landing-boton landing-boton--primario" href="#vitrina">
              Descubrir el marketplace <span aria-hidden="true">↗</span>
            </a>
            <a className="landing-boton landing-boton--secundario" href="#como-funciona">Ver cómo funciona</a>
          </div>
          <div className="landing-confianza" aria-label="Ventajas de Marketplace UM">
            <span><b>✓</b> Comunidad verificada</span>
            <span><b>✓</b> Cerca de ti</span>
            <span><b>✓</b> Sin intermediarios</span>
          </div>
        </div>

        <div className="landing-escena" aria-label="Vista de publicaciones de Marketplace UM">
          <div className="landing-orbita landing-orbita--uno" />
          <div className="landing-orbita landing-orbita--dos" />
          <div className="landing-app-centro">
            <span className="landing-app-pulso" />
            <img src="/icon.png" alt="Marketplace UM" width="88" height="88" />
            <strong>Todo cerca.</strong><small>Todo en comunidad.</small>
          </div>
          {productos.map((producto, indice) => (
            <a className={`landing-mini-producto landing-mini-producto--${indice + 1}`} href={`/producto/${producto.id}`} key={producto.id}>
              <img src={urlFoto(producto.fotos[0])} alt="" />
              <span><small>{producto.categoria?.nombre ?? 'Marketplace UM'}</small><strong>{producto.titulo}</strong><b>{precio(producto.precio)}</b></span>
            </a>
          ))}
          {productos.length === 0 && (
            <>
              <div className="landing-mini-producto landing-mini-producto--1 landing-mini-texto"><span><small>Para tus clases</small><strong>Libros y apuntes</strong><b>Cerca de ti</b></span></div>
              <div className="landing-mini-producto landing-mini-producto--2 landing-mini-texto"><span><small>Hecho en la UM</small><strong>Comida y negocios</strong><b>Descubre</b></span></div>
              <div className="landing-mini-producto landing-mini-producto--3 landing-mini-texto"><span><small>Entre estudiantes</small><strong>Tecnología y más</strong><b>Conecta</b></span></div>
            </>
          )}
          <div className="landing-alerta-flotante"><span>✓</span> Publicación nueva cerca de ti</div>
        </div>
      </section>

      <div className="landing-marquesina" aria-hidden="true"><div>
        {[...categorias, ...categorias].map((categoria, indice) => <span key={`${categoria}-${indice}`}>{categoria}<i>✦</i></span>)}
      </div></div>

      <section className="landing-seccion landing-vitrina" id="vitrina">
        <div className="landing-seccion-cabeza">
          <div><p className="landing-eyebrow"><span>✦</span> Recién llegado</p><h2>Siempre hay algo<br />que vale la pena descubrir.</h2></div>
          <p>Explora publicaciones de personas y negocios que forman parte de tu misma comunidad.</p>
        </div>
        <div className="landing-grid-productos">
          {productos.length > 0 ? productos.map((producto, indice) => (
            <a className="landing-producto" href={`/producto/${producto.id}`} key={producto.id}>
              <div className="landing-producto-imagen"><img src={urlFoto(producto.fotos[0])} alt={producto.titulo} /><span>{indice === 0 ? 'Nuevo' : producto.categoria?.nombre ?? 'Descubre'}</span></div>
              <div className="landing-producto-info"><div><small>{producto.vendedor?.nombre ?? 'Comunidad UM'}</small><h3>{producto.titulo}</h3></div><strong>{precio(producto.precio)}</strong></div>
            </a>
          )) : categorias.slice(0, 3).map((categoria, indice) => (
            <div className={`landing-producto landing-producto-vacio landing-producto-vacio--${indice + 1}`} key={categoria}>
              <div className="landing-producto-imagen"><span>Explora</span><b>{categoria}</b></div>
              <div className="landing-producto-info"><div><small>Comunidad UM</small><h3>Algo nuevo te espera</h3></div><strong>↗</strong></div>
            </div>
          ))}
        </div>
      </section>

      <section className="landing-seccion landing-como" id="como-funciona">
        <div className="landing-como-intro"><p className="landing-eyebrow"><span>✦</span> Fácil, local y humano</p><h2>Menos vueltas.<br />Más comunidad.</h2><p>Marketplace UM hace sencillo encontrar eso que necesitas y darle una segunda vida a lo que ya no usas.</p></div>
        <ol className="landing-pasos">
          <li><span>01</span><div><h3>Descubre</h3><p>Explora lo que personas y negocios de la UM tienen para ofrecer.</p></div></li>
          <li><span>02</span><div><h3>Conecta</h3><p>Habla directamente con quien publica, sin intermediarios ni complicaciones.</p></div></li>
          <li><span>03</span><div><h3>Hazlo cerca</h3><p>Coordina dentro de tu comunidad, de forma práctica y más confiable.</p></div></li>
        </ol>
      </section>

      <section className="landing-cierre">
        <div className="landing-cierre-luz" /><img src="/icon.png" alt="" width="62" height="62" />
        <p className="landing-eyebrow"><span>✦</span> Esto apenas comienza</p>
        <h2>Lo mejor de la UM,<br />más cerca que nunca.</h2>
        <p>Compra, vende, descubre y conecta con una comunidad que se mueve contigo.</p>
        <a className="landing-boton landing-boton--claro" href="#vitrina">Quiero explorar <span>→</span></a>
      </section>

      <footer className="landing-footer">
        <a className="landing-marca" href="#inicio"><img src="/icon.png" alt="" width="34" height="34" /><span>Marketplace UM</span></a>
        <p>Hecho para la comunidad de la Universidad de Montemorelos.</p><a href="/privacidad">Privacidad</a>
      </footer>
    </main>
  );
}
