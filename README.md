# Musicfy

Un player flotante para **Music y Spotify** en macOS. Siempre a la vista: arriba
de todas las ventanas, en todos los escritorios y también sobre apps en pantalla
completa. Muestra lo que esté sonando en cualquiera de las dos.

## Modos

| Modo | Tamaño | Cómo es |
|---|---|---|
| **Tapa** | 320 × 320 | Sólo la tapa. Al pasar el mouse aparecen los controles sobre un vidrio. |
| **Compacto** | 320 × 144 | Miniatura, título, tiempo y controles. El fondo toma el color de la tapa. |
| **Isla** | 300 × 44 | Cápsula arriba al centro de la pantalla. Se abre hacia abajo al pasar el mouse. |

- **Doble clic** en una parte vacía: alterna tapa y compacto.
- **Clic derecho** en el player o en el ícono de la barra de menú: el menú.
- **Clic** en el ícono de la barra de menú: muestra o esconde el player.
- Cuando no suena nada, la tapa pasa sola a compacto y vuelve cuando arranca la
  música (se puede cambiar por "quedarse" o "esconderse").

Arriba a la derecha: **letras** sincronizadas (de [LRCLIB](https://lrclib.net)),
**volumen** de la app y **salida de audio** del Mac. En el menú "Botones" se
elige cuáles se ven.

## Instalar

Hace falta macOS 14 o más nuevo y las herramientas de línea de comandos de Xcode
(`xcode-select --install`).

```bash
git clone https://github.com/pedrocela/musicfy.git
cd musicfy
./build.sh --install
```

La primera vez, macOS pregunta si Musicfy puede controlar Music y Spotify:
hay que decir que sí. Si se negó por error: Ajustes del Sistema → Privacidad y
seguridad → Automatización → Musicfy.

Para que arranque sola: menú → "Abrir al iniciar sesión".

## Cómo funciona

- Lee y controla las apps por **AppleScript** (lo único que Music y Spotify
  dejan usar desde afuera). Nunca las abre por su cuenta: cada script pregunta
  antes si la app está abierta.
- Se entera de los cambios al instante por las notificaciones que publican las
  dos apps, y además lee el estado cada 1,5 s. La barra de progreso se interpola
  entre lecturas.
- Si Music no da la tapa (pasa con temas de Apple Music que no están en la
  biblioteca), la busca en el catálogo público de iTunes.

## Código

```
Sources/Musicfy/
  App/      ventana flotante, barra de menú, menús, modos y mouse
  Engine/   Music y Spotify, estado, tapa, colores, letras, salida de audio
  UI/       vistas SwiftUI; Theme.swift tiene medidas, colores y animaciones
```
