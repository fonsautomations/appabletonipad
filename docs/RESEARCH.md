# Investigación: qué echan en falta los live performers (y qué hace StageDeck al respecto)

Fecha: octubre 2026. Fuentes: foro de Loopy Pro (hilo LK vs touchAble Pro), Elektronauts (sequencer
threads), documentación y foro de AbleSet, reseñas de App Store de LK / touchAble Pro / Grip,
documentación de AbletonOSC, CDM, Decoded Magazine. Reddit no era accesible desde este entorno de
forma directa; los hilos de r/ableton y r/synthesizers aparecen citados a través de búsquedas y de
los foros que los replican. Conviene repetir la pasada por Reddit con el iPad en la mano cuando la
app esté en uso.

## 1. Lo que dice la gente

### Controladores de iPad para Ableton (LK, touchAble Pro, Grip, TouchOSC)

| Queja / deseo recurrente | Fuente | StageDeck |
|---|---|---|
| Faders "a saltos" (stepping audible en fades y barridos de filtro) | reseñas LK | Faders con gesto relativo y envío coalescido cada 30 ms con valor float completo (no 0‑127). |
| Wi‑Fi poco fiable en el escenario; "úsalo por cable" | Loopy Pro forum, BWX deck | OSC por UDP funciona igual por Ethernet; descubrimiento automático; reconexión; indicador de estado y de último mensaje. |
| touchAble "hace de todo" pero es complejo; LK "simple pero limitado" | Loopy Pro forum, CDM | Tres pantallas, cada una pensada para tocar; lo avanzado está en Ajustes, no encima de los clips. |
| touchAble deja de funcionar con versiones nuevas de Live; LK consume CPU | Loopy Pro forum | Puente open‑source (AbletonOSC) mantenido por la comunidad, con código en el repo para arreglar lo que se rompa. |
| Ver el nombre y color reales de cada clip, no un pad genérico | BWX, Decoded Magazine | Nombres y colores de Live, prefijo/etiqueta separados ("basilar_5-" / "HI PERC"), barra de progreso, *queued* parpadeando. |
| Perder la referencia de en qué parte del set estás | AbleSet docs/foro | Secciones automáticas por nombre de escena, "sección actual" en la barra inferior, seguir la escena en reproducción. |
| Letras / notas / qué sintetizador usar visibles en el escenario | Max for Live "Text notes for Session View", AbleSet lyrics | Nota por clip (y por escena en el modelo) guardada en el perfil, visible dentro del clip; modo texto grande. |
| Miedo al "click equivocado" (una escena mal lanzada se oye en toda la sala) | BWX deck, hilos de live sets | Bloqueo de actuación, confirmación de STOP ALL y de escena, lanzar sólo con pulsación larga, háptica. |
| Cue de cada stem antes de subirlo | BWX, DJs | Fila CUE (solo/cue de Live) y fader de cue volume (vía la extensión master). |

### Secuenciadores (Elektron, Oxi One, apps de iPad)

| Lo que valoran | Fuente | StageDeck |
|---|---|---|
| P‑locks por paso, probabilidad, condiciones de trig, retrig | Elektronauts | Implementado en el motor (ver tests `SequencerTests`). |
| Varios LFOs por pista modulando CC | Elektronauts (Digitakt/Digitone) | 2 LFOs por pista: 7 formas, sync a tempo, modos free/trig/one‑shot, destino CC / pitch bend / velocidad. |
| Longitud y escala de tiempo por pista (polimetría), micro‑timing, swing | Digitakt II specs, Elektronauts | Longitud 1‑64, velocidad 2x…1/8x, micro ±11 ticks, swing global y por pista. |
| Euclídeo, random, modos de dirección | Oxi One reviews | Panel TOOLS: euclid con rotación, random con densidad y escala, shift, humanize; direcciones ←, →, ↔, ?. |
| Acordes y modo armónico, escalas | Oxi One ("harmonizer"), Digitakt keyboard mode | Acordes por paso (min, maj, 7, sus…), 18 escalas, *scale lock* por pista, teclado de pantalla en escala. |
| Cadena de patrones y modo canción para tocar sets enteros | Elektronauts "song mode" | Loop / chain / song con repeticiones, cambio de patrón cuantizado al final del ciclo, cola visible. |
| Botón FILL para variaciones sin editar | Elektron | FILL en la barra de transporte; condiciones FILL / !FILL. |
| Que sea el "cerebro" de varios cacharros por MIDI con clock estable | Elektronauts ("not ideal as central brain") | Puerto por pista, clock MIDI con timestamps CoreMIDI, esclavo a clock externo, panic. |
| Apps de iPad: el loop se pierde al parar, clock inestable, sync a Ableton Link | Gearspace, reseñas Modstep | Transporte independiente del de Live (o siguiéndolo), clock por marcas de tiempo; Link queda en la hoja de ruta. |

## 2. Qué tiene BWX Launcher (referencia) y qué añade StageDeck

BWX (deck de 23 páginas): launcher con nombres/colores, queued/playing con progreso, grupos K/R,
secciones por nombre de escena, cue por stem, dos decks de 10 columnas, vista individual, mixer con
faders + vúmetro, LPF por stem, HPF por deck, envíos, botón de corte por deck, master/play/sync,
cable directo Mac‑iPad, modo demo, 8 idiomas.

StageDeck cubre todo eso (salvo idiomas, por ahora en inglés) y añade: notas por clip, secuenciador
completo, salida MIDI a hardware y a Live, clock in/out, decks y grupos definidos por el usuario (no
sólo A/B fijos), bloqueo de actuación y confirmaciones, texto grande, perfil persistente, cue
volume y master por OSC (extensión propia), núcleo con tests.

## 3. Hoja de ruta sugerida (por valor para un directo)

1. **Ableton Link** en el secuenciador (LinkKit es un binario de Ableton que hay que descargar con
   su licencia; no se puede incluir en el repo).
2. **Setlist**: orden de secciones/escenas con "siguiente" en grande y cuenta de compases, al estilo AbleSet.
3. **Macros de dispositivo configurables** (cualquier parámetro de cualquier dispositivo como fader en el mixer), no sólo Auto Filter.
4. **Arpegiador** por pista y modo "multitrack" de batería (Oxi).
5. **Grabación de automatización** de CC en lanes (dibujar curvas por paso).
6. Idiomas (ES/EN al menos) y modo claro para ensayos.
7. Página de "performance" totalmente personalizable (botones libres mapeados a OSC/MIDI).

## 4. Referencias

- AbletonOSC: https://github.com/ideoforms/AbletonOSC
- Loopy Pro forum, "LK or Touchable Pro for Ableton?": https://forum.loopypro.com/discussion/38164/lk-or-touchable-pro-for-ableton
- LK en App Store (reseñas): https://apps.apple.com/us/app/lk-ableton-midi-controller/id944972221
- Grip en App Store: https://apps.apple.com/us/app/grip-control-ableton-live/id6758132290
- CDM sobre LK: https://cdm.link/lk-gives-ipad-android-tablet-easy-control-ableton-live/
- Decoded Magazine, road test LK: https://www.decodedmagazine.com/erik-pettersson-road-tests-the-lk-live-controller-for-ableton-live/
- Elektronauts, Digitakt/Digitone como secuenciador vs competencia: https://www.elektronauts.com/t/digitakt-digitone-as-a-midi-sequencer-vs-competition/232107
- Elektronauts, hilo Oxi One: https://www.elektronauts.com/t/oxi-one-hardware-sequencer/141839
- Digitakt II specs (Andertons): https://www.andertons.co.uk/elektron/elektron-digitakt-ii
- AbleSet docs: https://ableset.com/docs y foro https://forum.ableset.app
- Text notes for Session View (M4L): https://abletonkurse.gumroad.com/l/text-notes-for-ableton-session-view
- Gearspace, "What's the best iPad MIDI sequencer?": https://gearspace.com/threads/whats-the-best-ipad-midi-sequencer.833946/
- Apple, CABTMIDICentralViewController: https://developer.apple.com/documentation/coreaudiokit/cabtmidicentralviewcontroller
- Apple, MIDINetworkSession: https://developer.apple.com/documentation/coremidi/midinetworksession
