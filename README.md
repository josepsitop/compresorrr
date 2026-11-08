# Squeeze

Comprime **fotos, videos, PDF y archivos** en Android y Windows con un solo código (Flutter + FFmpeg).

## Compilar en GitHub (sin instalar nada)
1. Crea un repositorio en GitHub y sube **todo el contenido de esta carpeta** (incluida `.github`).
2. Ve a **Actions → Compilar Squeeze → Run workflow**.
3. Espera unos 15–25 minutos. Al terminar, abre la ejecución y descarga el artefacto **Squeeze-Todo**.
4. Dentro del zip hay:
   - `Squeeze-Android.apk`: cópialo al celular e instálalo (permite "instalar apps desconocidas").
   - `Squeeze-Windows.zip`: descomprímelo y abre `squeeze.exe`. No necesita instalación.
5. Si subes un tag (`git tag v0.1.0 && git push --tags`), el APK y el zip de Windows también quedan en **Releases**.

## Qué hace cada pestaña
- **Fotos**: WebP / JPEG, reducción de tamaño, modo sin pérdida y modo personalizado. Muestra antes y después.
- **Videos**: 7 modos + personalizado, cambio de contenedor (MP4, MKV, MOV) y **vista previa** de 2–20 % del video con estimación del peso final.
- **Archivos**: PDF (Ghostscript en PC, modo imagen en Android) y compresión sin pérdida (GZip en Android; 7-Zip y ZIP en PC).
- Cada modo tiene un botón ⓘ que explica qué significa y cómo se compara con los demás, y un botón **Comparar**.

## Versión PC y tu RTX 3060 Ti
- Usa un `ffmpeg.exe` completo (incluido en el build) con **NVENC**: el modo "Rápido por hardware" codifica HEVC en la GPU.
- Los modos lentos (HEVC *slow*, AV1) corren en el procesador, que comprime más por MB.
- La 3060 Ti **no puede codificar AV1** (solo decodificarlo); por eso AV1 va por CPU.
- Si NVENC no está disponible, el modo hardware pasa solo a x265 por CPU.

## Límites conocidos
- No se compiló ni probó en este entorno: **el primer build puede fallar** por detalles de versiones. Copia el error del log de Actions y se corrige.
- El APK pesa bastante (~70–120 MB) porque lleva FFmpeg completo con x265.
- Videos HDR/10 bits se convierten a 8 bits SDR.
- AV1 en Android no está incluido (la build de FFmpeg para móvil no garantiza ese códec).
- Los PDF en "modo imagen" pierden el texto seleccionable. En PC usa los modos Ghostscript.
- En Android, el selector de archivos copia el video a la caché antes de procesarlo: necesitas espacio libre extra.
- Licencias: FFmpeg (GPL), Ghostscript (AGPL) y 7-Zip (LGPL) van incluidos. Para uso personal no hay problema; si distribuyes la app, revisa sus licencias.

## Siguientes mejoras posibles
Arrastrar y soltar en PC, ícono propio, cola en segundo plano en Android, recompresión de imágenes dentro de DOCX/PPTX, comparador deslizante antes/después.
