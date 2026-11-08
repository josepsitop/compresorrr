import 'models.dart';
import 'tools.dart';

const List<Preset> kAllPresets = [
  // ------------------------------------------------------------- VIDEO
  Preset(
    id: 'hw', kind: Kind.video, name: 'Rápido por hardware',
    tagline: 'Usa el chip de video: minutos en vez de horas.',
    savings: '40–65 %', speed: 5, quality: 3,
    explain: 'Tu equipo tiene un circuito dedicado a codificar video (NVENC en tu RTX, MediaCodec en el celular). '
        'Trabaja muy rápido y casi no gasta batería, pero es menos eficiente que un codificador por software: '
        'a la misma calidad el archivo sale algo más grande.',
    versus: 'Frente a Equilibrado: mucho más rápido, pero suele pesar entre 10 y 30 % más. '
        'Elígelo cuando tienes muchos videos o poco tiempo.',
  ),
  Preset(
    id: 'balanced', kind: Kind.video, name: 'Equilibrado (HEVC)', recommended: true,
    tagline: 'La mejor relación entre peso y calidad.',
    savings: '50–75 %', speed: 3, quality: 4,
    explain: 'HEVC (H.265) guarda el mismo video con cerca de la mitad de datos que H.264. '
        'Se usa CRF, que es calidad constante: no fijas un peso, fijas una calidad y el codificador gasta bits '
        'solo en las escenas difíciles. Con CRF 25–26 el resultado se ve igual al original a distancia normal.',
    versus: 'Frente a Casi idéntico: pesa bastante menos y la diferencia solo se ve ampliando la imagen. '
        'Frente a Máxima compresión: es mucho más rápido.',
  ),
  Preset(
    id: 'visual', kind: Kind.video, name: 'Casi idéntico',
    tagline: 'Conserva hasta el último detalle.',
    savings: '30–55 %', speed: 2, quality: 5,
    explain: 'Usa CRF 20 y un análisis más lento para ahorrar bits sin tocar texturas ni bordes. '
        'Ahorras menos que con Equilibrado, pero es lo más cercano a no perder nada sin llegar a compresión '
        'sin pérdida (que pesaría casi lo mismo que el original).',
    versus: 'Frente a Equilibrado: pesa entre 1,5 y 2 veces más y tarda más. '
        'Solo conviene si vas a editar, ampliar o archivar.',
  ),
  Preset(
    id: 'max', kind: Kind.video, name: 'Máxima compresión',
    tagline: 'El archivo más pequeño en HEVC.',
    savings: '65–85 %', speed: 1, quality: 3,
    explain: 'Sube el CRF a 28 y usa un modo de análisis lento: el codificador prueba muchas más combinaciones '
        'para encontrar la más pequeña. Mirando de cerca puedes notar suavizado en texturas finas '
        '(pasto, cabello, tela). En celular tarda mucho; en PC es razonable.',
    versus: 'Frente a Equilibrado: pesa cerca de un tercio menos, a cambio de algo de detalle fino '
        'y bastante más tiempo.',
  ),
  Preset(
    id: 'social', kind: Kind.video, name: 'Mini para compartir',
    tagline: 'Máximo 720p, ideal para chats.',
    savings: '80–95 %', speed: 4, quality: 2,
    explain: 'Limita la resolución a 720p, usa CRF 29 y audio de 96 kbps. En pantalla de celular casi no se nota; '
        'en una TV grande sí. Es la opción que más reduce el peso para enviar por WhatsApp o Telegram.',
    versus: 'Frente a Equilibrado: mucho más pequeño, pero pierde resolución si el original es 1080p o 4K.',
  ),
  Preset(
    id: 'compat', kind: Kind.video, name: 'Compatible (H.264)',
    tagline: 'Se abre en cualquier dispositivo.',
    savings: '25–55 %', speed: 4, quality: 4,
    explain: 'H.264 es el códec más universal: lo reproduce cualquier TV, auto, celular viejo o editor. '
        'Es menos eficiente que HEVC: a igual calidad pesa entre 30 y 50 % más.',
    versus: 'Frente a Equilibrado: más pesado, pero sin riesgo de que no abra en algún aparato.',
  ),
  Preset(
    id: 'av1', kind: Kind.video, name: 'AV1 extremo (solo PC)', pcOnly: true, needs: 'svtav1',
    tagline: 'El códec más eficiente que existe hoy.',
    savings: '65–90 %', speed: 1, quality: 4,
    explain: 'AV1 es el códec abierto más eficiente: a igual calidad suele pesar entre 20 y 30 % menos que HEVC. '
        'Se codifica con el procesador: la RTX 3060 Ti puede decodificar AV1 pero no codificarlo '
        '(eso empezó con la serie RTX 40). Se reproduce bien en PC, navegadores y Android reciente; '
        'algunos TV y celulares antiguos no.',
    versus: 'Frente a Máxima compresión (HEVC): algo más pequeño o mejor calidad al mismo peso, '
        'pero compatible con menos aparatos.',
  ),
  Preset(
    id: 'custom', kind: Kind.video, name: 'Personalizado',
    tagline: 'Tú eliges códec, calidad, resolución y audio.',
    savings: 'Variable', speed: 3, quality: 3,
    explain: 'Ajusta los parámetros tú mismo. CRF es la calidad objetivo: más bajo es mejor calidad y más peso '
        '(18 casi sin pérdida, 23 muy buena, 28 aceptable, 32 se nota). La resolución y el audio también cuentan: '
        'bajar de 4K a 1080p reduce mucho el peso.',
    versus: 'Combínalo con la vista previa para probar ajustes sin esperar el video completo.',
  ),

  // ------------------------------------------------------------- FOTOS
  Preset(
    id: 'p_web', kind: Kind.photo, name: 'WebP alta calidad',
    tagline: 'Misma resolución, bastante menos peso.',
    savings: '40–70 %', speed: 5, quality: 5,
    explain: 'WebP usa una compresión más moderna que JPEG. Con calidad visual equivalente suele pesar entre '
        '25 y 35 % menos. Lo abren Android, navegadores y casi todas las apps, pero algunos editores antiguos no.',
    versus: 'Frente a JPEG premium: más pequeño y un poco menos compatible.',
  ),
  Preset(
    id: 'p_jpg', kind: Kind.photo, name: 'JPEG premium',
    tagline: 'Compatible con absolutamente todo.',
    savings: '20–50 %', speed: 5, quality: 5,
    explain: 'Vuelve a guardar la foto como JPEG de calidad cercana a 90 conservando la resolución. '
        'Es el formato que abre cualquier programa. Ahorras menos que con WebP porque JPEG es más antiguo.',
    versus: 'Frente a WebP: pesa más, pero no tendrás problemas de compatibilidad.',
  ),
  Preset(
    id: 'p_bal', kind: Kind.photo, name: 'Equilibrado', recommended: true,
    tagline: 'WebP 80 y lado mayor de 2560 px.',
    savings: '70–90 %', speed: 5, quality: 4,
    explain: 'Reduce la foto a 2560 px en el lado mayor (suficiente para pantallas e impresiones de unos '
        '20 × 25 cm) y la guarda en WebP calidad 80. En pantalla es difícil distinguirla del original.',
    versus: 'Frente a WebP alta calidad: pesa mucho menos porque baja la resolución; '
        'no lo uses si piensas recortar o imprimir en grande.',
  ),
  Preset(
    id: 'p_min', kind: Kind.photo, name: 'Mínimo para chat',
    tagline: 'WebP 70 y lado mayor de 1600 px.',
    savings: '85–97 %', speed: 5, quality: 2,
    explain: 'Reduce a 1600 px y calidad 70. Perfecta para mensajería o formularios. '
        'Al ampliar o imprimir se nota la pérdida.',
    versus: 'Frente a Equilibrado: bastante más pequeña, con pérdida visible al ampliar.',
  ),
  Preset(
    id: 'p_lossless', kind: Kind.photo, name: 'WebP sin pérdida',
    tagline: 'Para capturas y gráficos: ni un píxel cambia.',
    savings: '20–45 %', speed: 4, quality: 5,
    explain: 'Guarda cada píxel exactamente igual, con un método más eficiente que PNG. Sirve para capturas de '
        'pantalla, logos y diagramas. Con fotos JPEG el resultado suele pesar más: no lo uses para eso.',
    versus: 'Frente a los demás modos: es el único que no altera nada y también el que menos ahorra.',
  ),
  Preset(
    id: 'custom', kind: Kind.photo, name: 'Personalizado',
    tagline: 'Formato, calidad y tamaño a tu medida.',
    savings: 'Variable', speed: 5, quality: 3,
    explain: 'Elige formato (WebP o JPEG), calidad de 40 a 95 y un tamaño máximo. Calidad 80 es un buen punto de '
        'partida; por debajo de 60 empiezan a verse bloques en degradados y cielos.',
    versus: 'Ideal para ajustar a un límite de peso concreto (por ejemplo, formularios que piden menos de 1 MB).',
  ),

  // ----------------------------------------------------------- ARCHIVOS
  Preset(
    id: 'f_7z', kind: Kind.file, group: 'generic', pcOnly: true, needs: '7z', recommended: true,
    name: '7-Zip LZMA2 ultra',
    tagline: 'La mayor compresión sin pérdida.',
    savings: '0–95 %', speed: 1, quality: 5,
    explain: 'LZMA2 con diccionario grande analiza el archivo a fondo y suele pesar entre 10 y 30 % menos que ZIP '
        'en datos compresibles (texto, registros, CSV, código, ejecutables). Es lento, usa bastante RAM y para '
        'abrirlo hace falta 7-Zip o similar. No hace magia con archivos ya comprimidos (JPG, MP4, DOCX).',
    versus: 'Frente a ZIP y GZip: más pequeño, pero más lento y menos universal.',
  ),
  Preset(
    id: 'f_zip', kind: Kind.file, group: 'generic', pcOnly: true, needs: '7z',
    name: 'ZIP máximo',
    tagline: 'El formato que todo el mundo sabe abrir.',
    savings: '0–85 %', speed: 3, quality: 5,
    explain: 'Deflate al máximo dentro de un contenedor ZIP, que Windows, Mac, Android y iPhone abren sin '
        'instalar nada. Sin pérdida de datos.',
    versus: 'Frente a 7-Zip: lo abre cualquiera, pero pesa algo más.',
  ),
  Preset(
    id: 'f_gz', kind: Kind.file, group: 'generic', recommended: true,
    name: 'GZip nivel 9',
    tagline: 'Sin pérdida, funciona también en el celular.',
    savings: '0–90 %', speed: 4, quality: 5,
    explain: 'Comprime sin perder datos con Deflate al máximo. Funciona muy bien con texto, registros, CSV, código '
        'o bases de datos (60–90 %) y casi nada con archivos ya comprimidos (JPG, MP4, ZIP, DOCX, XLSX). '
        'Genera un .gz que abren 7-Zip, WinRAR y la mayoría de gestores de archivos de Android.',
    versus: 'Frente a 7-Zip: se abre en más lugares, pero comprime menos.',
  ),
  Preset(
    id: 'pdf_gs_ebook', kind: Kind.file, group: 'pdf', pcOnly: true, needs: 'gs', recommended: true,
    name: 'Inteligente (conserva el texto)',
    tagline: 'Imágenes a 150 dpi; el texto sigue seleccionable.',
    savings: '40–90 %', speed: 4, quality: 4,
    explain: 'Usa Ghostscript para reducir solo lo que pesa: las imágenes pasan a 150 dpi y se recomprimen, y las '
        'fuentes se optimizan. El texto sigue siendo texto: se puede buscar, seleccionar y copiar. '
        'Es el mejor equilibrio para documentos con fotos o escaneos.',
    versus: 'Frente a los modos de imagen: el texto queda nítido y buscable; los modos de imagen pesan menos en '
        'escaneos pero convierten todo en imagen.',
  ),
  Preset(
    id: 'pdf_gs_print', kind: Kind.file, group: 'pdf', pcOnly: true, needs: 'gs',
    name: 'Conservador (300 dpi)',
    tagline: 'Calidad de impresión.',
    savings: '10–50 %', speed: 4, quality: 5,
    explain: 'Imágenes a 300 dpi: se ven bien impresas. Ahorra menos, pero casi no cambia el aspecto.',
    versus: 'Frente a Inteligente: pesa más y se ve igual en pantalla.',
  ),
  Preset(
    id: 'pdf_gs_screen', kind: Kind.file, group: 'pdf', pcOnly: true, needs: 'gs',
    name: 'Pantalla (72 dpi)',
    tagline: 'El PDF más liviano que conserva el texto.',
    savings: '60–95 %', speed: 4, quality: 2,
    explain: 'Imágenes a 72 dpi: perfecto para leer en pantalla o enviar por correo. Impreso se ve borroso.',
    versus: 'Frente a Inteligente: bastante más pequeño, con imágenes de menor nitidez.',
  ),
  Preset(
    id: 'pdf_r_sharp', kind: Kind.file, group: 'pdf', recommended: true,
    name: 'Imagen nítida (150 dpi)',
    tagline: 'Cada página se convierte en imagen JPEG.',
    savings: '30–85 %', speed: 3, quality: 4,
    explain: 'Convierte cada página en una imagen JPEG de calidad 70 y arma un PDF nuevo. Funciona en el celular y '
        'reduce mucho los escaneos, pero el texto deja de ser seleccionable y buscable.',
    versus: 'Es el modo que funciona en Android. En PDFs de solo texto puede pesar más: en ese caso Squeeze no guarda el resultado.',
  ),
  Preset(
    id: 'pdf_r_compact', kind: Kind.file, group: 'pdf',
    name: 'Imagen compacta (110 dpi)',
    tagline: 'Más liviano, aún legible.',
    savings: '50–92 %', speed: 3, quality: 3,
    explain: 'Páginas como imagen a 110 dpi y calidad 55. Se lee bien en pantalla; el texto pequeño se nota más blando.',
    versus: 'Frente a Imagen nítida: más pequeño, con menos detalle en letra chica.',
  ),
  Preset(
    id: 'pdf_r_min', kind: Kind.file, group: 'pdf',
    name: 'Imagen mínima (80 dpi)',
    tagline: 'Lo más pequeño posible.',
    savings: '65–96 %', speed: 3, quality: 2,
    explain: 'Páginas como imagen a 80 dpi y calidad 45. Para enviar documentos por chat cuando solo importa que '
        'se pueda leer.',
    versus: 'Frente a Imagen compacta: más pequeño, pero la letra pequeña puede costar leerla.',
  ),
];

List<Preset> presetsFor(Kind k, {bool pdf = false}) {
  return kAllPresets.where((p) {
    if (p.kind != k) return false;
    if (k == Kind.file && (p.group == 'pdf') != pdf) return false;
    if (p.pcOnly && !Tools.isPc) return false;
    switch (p.needs) {
      case 'gs':
        return Tools.gs != null;
      case '7z':
        return Tools.sevenZip != null;
      case 'svtav1':
        return Tools.svtav1;
    }
    return true;
  }).toList();
}
