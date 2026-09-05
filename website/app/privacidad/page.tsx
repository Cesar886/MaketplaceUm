import type { Metadata } from 'next';

import { SITE_URL } from '@/lib/api';

export const metadata: Metadata = {
  title: 'Política de privacidad | Marketplace UM',
  description: 'Cómo Marketplace UM recopila, usa, comparte y protege los datos personales.',
  alternates: { canonical: `${SITE_URL}/privacidad` },
};

const secciones = [
  {
    titulo: '1. Responsable',
    contenido: <>Marketplace UM es una plataforma de compraventa para la comunidad de la Universidad de Montemorelos. Para preguntas sobre el tratamiento de datos personales, escríbenos a <a href="mailto:mercadito@um.edu.mx">mercadito@um.edu.mx</a>. Nuestro domicilio de contacto es Universidad de Montemorelos, Montemorelos, Nuevo León, México.</>,
  },
  {
    titulo: '2. Datos que recopilamos',
    contenido: <><p>Según las funciones que uses, podemos recopilar:</p><ul><li><strong>Datos de cuenta:</strong> nombre, correo electrónico, número telefónico y tipo de cuenta. Si inicias sesión con Google, recibimos los datos de perfil que autorices, como nombre, correo y foto.</li><li><strong>Datos de verificación:</strong> matrícula, carrera, semestre y, si solicitas verificación, imágenes de credencial universitaria, identificación oficial o documentos de negocio.</li><li><strong>Contenido que proporcionas:</strong> publicaciones, fotografías, precios, ubicación que decidas agregar, comentarios, preguntas, mensajes, favoritos, carrito y reportes.</li><li><strong>Datos técnicos y de uso:</strong> identificador de dispositivo, dirección IP, sistema operativo, versión de la app, búsquedas e interacciones con publicaciones.</li><li><strong>Notificaciones:</strong> token de Firebase Cloud Messaging y tus preferencias de notificación.</li></ul></>,
  },
  {
    titulo: '3. Para qué usamos los datos',
    contenido: <><p>Usamos los datos para crear y proteger tu cuenta; publicar y mostrar productos; facilitar la comunicación entre compradores y vendedores; verificar cuentas cuando lo solicites; enviar notificaciones relacionadas con actividad, mensajes, publicaciones o preferencias; personalizar el feed y mejorar la plataforma; atender reportes y cumplir obligaciones legales.</p><p>No vendemos tus datos personales ni los usamos para publicidad de terceros.</p></>,
  },
  {
    titulo: '4. Datos visibles y con quién se comparten',
    contenido: <><p>La información que publiques —como tu nombre de perfil, foto, calificación, publicaciones, fotos, comentarios, preguntas y datos de contacto que decidas mostrar— puede ser visible para otros usuarios. No publiques información que no quieras compartir.</p><p>Usamos proveedores que procesan datos para prestar el servicio: Google, para el inicio de sesión cuando lo eliges, y Firebase Cloud Messaging de Google, para notificaciones. Podemos divulgar datos si una autoridad competente lo requiere o cuando sea necesario para proteger derechos, seguridad o cumplir la ley.</p></>,
  },
  {
    titulo: '5. Permisos del dispositivo',
    contenido: <>La cámara se solicita únicamente cuando eliges tomar o escanear una imagen, por ejemplo al publicar, verificarte o escanear un código QR. Las notificaciones requieren tu autorización. La ubicación de un negocio es opcional y se agrega solo cuando la proporcionas; puedes negar permisos desde los ajustes de tu dispositivo.</>,
  },
  {
    titulo: '6. Conservación y seguridad',
    contenido: <>Conservamos los datos mientras tu cuenta esté activa o mientras sean necesarios para las finalidades descritas, resolver disputas y cumplir obligaciones legales. Aplicamos medidas técnicas y organizativas razonables para protegerlos, aunque ningún sistema es completamente seguro.</>,
  },
  {
    titulo: '7. Tus derechos y eliminación de cuenta',
    contenido: <>Puedes acceder, rectificar, cancelar u oponerte al tratamiento de tus datos, y solicitar la eliminación de tu cuenta desde los ajustes de la app o escribiendo a <a href="mailto:mercadito@um.edu.mx?subject=Derechos%20ARCO">mercadito@um.edu.mx</a> con el asunto “Derechos ARCO”. Atenderemos tu solicitud conforme a la legislación aplicable. Podremos conservar información limitada cuando sea indispensable por obligación legal o para resolver disputas.</>,
  },
  {
    titulo: '8. Menores de edad',
    contenido: <>Marketplace UM está dirigido a miembros de la comunidad universitaria. Si eres menor de edad, usa la plataforma solo con la autorización de tu madre, padre o tutor legal.</>,
  },
  {
    titulo: '9. Cambios a esta política',
    contenido: <>Podemos actualizar esta política para reflejar cambios en la plataforma o en la normativa. Publicaremos la versión vigente en esta página e indicaremos la fecha de actualización.</>,
  },
];

export default function PoliticaDePrivacidad() {
  return (
    <main className="contenedor politica-privacidad">
      <p className="pill pill--marca">Marketplace UM</p>
      <h1>Política de privacidad</h1>
      <p className="politica-actualizacion">Última actualización: 4 de septiembre de 2026</p>
      <p className="politica-intro">Esta política explica cómo Marketplace UM trata los datos personales al usar nuestra app y sitio web.</p>
      {secciones.map(({ titulo, contenido }) => (
        <section key={titulo} className="politica-seccion">
          <h2>{titulo}</h2>
          <div>{contenido}</div>
        </section>
      ))}
    </main>
  );
}
