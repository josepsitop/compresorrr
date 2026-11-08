# Squeeze

Comprime **fotos, videos, PDF y archivos** en Android (32 y 64 bits) y Windows con un solo código (Flutter + FFmpeg).

## Compilar en GitHub
1. Sube **todo el contenido de esta carpeta** a tu repositorio (incluida `.github` y `tool`). Si ya existe, GitHub reemplaza los archivos con el mismo nombre.
2. Ve a **Actions → Compilar Squeeze → Run workflow**.
3. Al terminar descarga el artefacto **Squeeze-Todo**: trae `Squeeze-Android.apk` y `Squeeze-Windows.zip`.
4. El APK funciona en celulares de 32 y de 64 bits (lleva las dos versiones, por eso pesa más).

## Qué hace
**Fotos**: WebP o JPEG, reducción de tamaño, modo sin pérdida, peso objetivo (200 KB, 500 KB, 1 MB…) y comparador deslizante antes/después.

**Videos**: 7 modos + personalizado. En **todos** los modos se puede cambiar el contenedor (MP4/MKV/MOV), el códec (HEVC/H.264/AV1 en PC), la resolución y el audio.
Extras: peso objetivo (10 MB, 25 MB…), recortar, quitar audio, solo audio (M4A/MP3), quitar ubicación y metadatos, reducir ruido, vista previa de 2–20 % con estimación del peso final y comparador de fotogramas.

**Archivos**: PDF y cualquier formato (ver tabla).

**Más**: espacio total ahorrado, historial, limpieza de temporales y datos de tu equipo.

Cada modo tiene un botón ⓘ que explica qué significa; y hay un botón **Comparar** y atajos "¿Para qué lo quieres?".

## Qué va en cada versión
| Función | Android | PC |
|---|---|---|
| Compresión de video/foto con presets, peso objetivo, recorte, audio | Sí | Sí |
| Aceleración por hardware | MediaCodec del celular | NVENC (tu RTX 3060 Ti) |
| AV1 | No | Sí (por CPU; la 3060 Ti no codifica AV1) |
| Calidad automática (VMAF) | No | Sí |
| PDF conservando el texto (Ghostscript) | No | Sí |
| PDF "modo imagen" | Sí | Sí |
| 7-Zip, ZIP, contraseña | No (solo GZip) | Sí |
| Compartir hacia Squeeze desde galería/WhatsApp | Sí | — |
| Compresión en segundo plano con notificación | Sí | — |
| Solo cuando esté cargando | Sí | — |
| Buscar los videos más pesados | Sí | — |
| Avisos según el celular (32 bits, poca RAM, sin HEVC por hardware) | Sí | — |
| Arrastrar y soltar | — | Sí |
| Carpeta vigilada | — | Sí |
| Menú del clic derecho de Windows | — | Sí |
| Cola de 2 videos a la vez con la GPU | — | Sí |

Lo que no funciona de verdad en Android (AV1, VMAF, Ghostscript, 7-Zip) está oculto en el APK y solo aparece en PC.

## Celulares de 32 bits o modestos
La app detecta el equipo. Si es de 32 bits, tiene poca RAM o pocos núcleos, preselecciona el modo más ligero (hardware si tiene HEVC, si no H.264) y avisa en cada modo pesado, por ejemplo: "este celular no aguanta HEVC por software" o "video 4K con poca memoria: baja a 1080p". Puedes ver los datos en **Más → Sobre este equipo**.

## Límites conocidos
- No se compiló ni probó en el entorno donde se escribió: **el primer build puede fallar**. Copia el error del log y se corrige.
- Falta OCR para devolver el texto seleccionable a los PDF en modo imagen (necesita Tesseract e idiomas; queda para una próxima versión).
- Las fotos se guardan sin metadatos ni perfil de color, así que una foto con color muy saturado (Display P3) puede verse un poco distinta.
- Videos HDR/10 bits se convierten a 8 bits SDR.
- En Android, el selector copia el archivo a la caché antes de procesarlo (necesitas espacio libre). "Más → Liberar espacio temporal" lo limpia.
- Para liberar espacio de verdad en el celular hay que borrar el original desde la galería (la app no lo borra sola).
- Con el menú del clic derecho, si seleccionas varios archivos se abre una ventana por archivo.
- Licencias: FFmpeg (GPL), Ghostscript (AGPL) y 7-Zip (LGPL) van incluidos. Para uso personal no hay problema; si distribuyes la app, revisa sus licencias.
