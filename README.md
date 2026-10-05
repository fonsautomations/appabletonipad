# StageDeck — launcher de clips, mixer de stems y secuenciador para Ableton Live en iPad

StageDeck es una app nativa de iPad (Swift / SwiftUI) para tocar en directo con Ableton Live
sin mirar el portátil, en la línea de BWX Launcher pero con más cosas:

| Pantalla | Qué hace |
|---|---|
| **LAUNCH** | Tu Session View por toque: clips con su nombre y color real, barra de progreso del clip, estado *queued* (parpadeo) / *playing*, dos decks (grupos de Live) o uno solo a lo grande, secciones automáticas (escenas `BASIL_1…BASIL_8` → botón **BASIL**), botones de grupo **K / R** (dispara sólo los kicks de una fila, o el resto), fila STOP, fila CUE, botón "cortar deck", notas por clip (letra, tonalidad, recordatorios) que se ven dentro del clip. |
| **MIXER** | Fader por stem con vúmetro en vivo y dB, envíos a cada retorno, macro de filtro por pista (Auto Filter de Live), HPF por deck (Auto Filter en la pista de grupo), mute / CUE / arm, master y cue volume. Todo cabe en pantalla sin desplazar: los decks se reparten en filas y los strips se adaptan a la altura; pestañas ALL / deck para ver uno solo a lo grande; el master siempre visible. Editable: qué envíos se ven, strips de grupo, filtro del master y **buses** (grupos, retornos, master o cualquier pista como canal propio con envíos, filtro y fader). |
| **CTRL** | Controlador editable: páginas de knobs, faders, botones, toggles y pads XY que tú colocas. Cada control se asigna a un parámetro de Live (pista → dispositivo → parámetro, por ejemplo las Macro 1‑8 de un rack) por OSC con feedback, o a un CC / nota MIDI para mapearlo en Live con MIDI Map o mandarlo a hardware. |
| **SEQ** | Secuenciador por pasos tipo Elektron / Oxi One: 16 pistas, hasta 64 pasos, p-locks (CC por paso), condiciones de trig (1:2, 2:4, FILL, PRE, NEI, 1ST…), probabilidad, retrig/ratchet con rampa, micro-timing, swing, acento y **slide** (estilo TB-303), acordes por paso, longitud y velocidad por pista (polimetría, 2x…1/8x), dirección (←, →, ping-pong, random), 2 LFOs por pista (CC, pitch bend o velocidad), lanes de CC, escalas y *scale lock*, euclídeo, random, botón FILL, cadenas de patrones y modo canción, grabación en vivo desde el teclado de pantalla. Sale por MIDI a Ableton o a hardware, con MIDI clock, o se esclaviza a clock externo. |

**Nombres editables y plantillas.** Cada canal se puede renombrar (mantén pulsado el nombre en el
launcher o en el mixer, o en Ajustes → Channel names); el nombre vale para launcher, mixer y
controles y viaja dentro de las plantillas. Una plantilla es un archivo `.stagedeck` (JSON) con
páginas de control, decks, grupos, nombres, notas, layout y patrones: se importa desde Archivos,
AirDrop o pegando el texto, con vista previa de lo que falta en tu set, y se exporta desde Ajustes.
Formato y cómo pedirle una a una IA: [`docs/TEMPLATE_FORMAT.md`](docs/TEMPLATE_FORMAT.md).

**Importar un proyecto de Live (.als).** Ajustes → Templates → Import an Ableton Live Set: la app
lee el archivo (sin Live abierto) y saca pistas, grupos, colores, escenas, retornos, clips y los
racks con el nombre de sus macros. Con eso puedes navegar el set en modo offline, crear los decks a
partir de los grupos y generar páginas CTRL con las macros de cada rack (una página por grupo).
Como todo va por nombre, al conectar con Live esos controles mueven los racks reales.

**Biblioteca y comprobación.** Ajustes → Library guarda dentro de la app setups completos,
proyectos del secuenciador (también desde SEQ → PATTERNS → SAVE PROJECT / LOAD) y plantillas, con
cargar, sobrescribir, renombrar, compartir y borrar. Ajustes → Set check compara tu configuración
con el set cargado y lista nombres de canal, notas de clip, decks, grupos y controles que apuntan a
pistas, clips o dispositivos que ya no existen, con un botón para limpiar lo obsoleto.

Todo es configurable desde Ajustes: tamaño y tipografía de los clips, qué filas mostrar, decks y
grupos de lanzamiento, modo "texto grande", bloqueo de actuación, confirmaciones, háptica, etc.
Hay un **modo demo** para probar todas las pantallas sin Live.

## Cómo funciona la conexión

```
 iPad (StageDeck)                            Mac (Ableton Live 11/12)
 ┌─────────────────┐   OSC/UDP 11000 →       ┌────────────────────────┐
 │ Launcher, Mixer │ ──────────────────────▶ │ AbletonOSC remote      │
 │                 │ ◀────────────────────── │ script (+ extensión    │
 │                 │   ← OSC/UDP 11001       │ master/retornos)       │
 │ Secuenciador    │   MIDI (red, BT, USB)   │ Pistas MIDI / hardware │
 └─────────────────┘ ──────────────────────▶ └────────────────────────┘
```

* **OSC bidireccional** sobre Wi‑Fi o cable Ethernet (adaptador USB‑C → Ethernet en el iPad y en el
  Mac, o un pequeño switch). Live envía de vuelta nombres, colores, estado de reproducción,
  posición de los clips, vúmetros, tempo… StageDeck encuentra el Mac sola por broadcast; si no, se
  escribe la IP en Ajustes.
* **MIDI** para el secuenciador y para hardware: Network MIDI (Audio MIDI Setup del Mac),
  **Bluetooth MIDI** (el iPad puede buscar dispositivos o anunciarse como periférico), USB
  (interfaz MIDI por hub USB‑C, o cable al Mac con IDAM) y un puerto virtual "StageDeck" para otras
  apps del iPad. El clock MIDI se envía con marcas de tiempo CoreMIDI (precisión de muestra).

## Instalar en tu iPad (primera vez, unos 10 minutos)

Necesitas un Mac con **Xcode 16 o superior** (gratis en la App Store) y un cable para el iPad.

1. Clona este repositorio y abre `StageDeck.xcodeproj`.
2. En el navegador de Xcode selecciona el proyecto → target **StageDeck** → pestaña *Signing &
   Capabilities* → elige tu *Team* (tu Apple ID; con un Apple ID gratuito vale, la app caduca a
   los 7 días y se vuelve a instalar con un clic; con cuenta de desarrollador de pago dura un año
   y puedes usar TestFlight).
3. Conecta el iPad, elígelo como destino arriba y pulsa **Run** (⌘R). La primera vez el iPad te
   pedirá confiar en el desarrollador en *Ajustes → General → VPN y gestión de dispositivos*.
4. La app es sólo horizontal, con la pantalla siempre encendida mientras está abierta.

## Instalar el puente en Ableton (2 minutos)

1. Copia la carpeta `ableton/AbletonOSC` a
   `~/Music/Ableton/User Library/Remote Scripts/` (créala si no existe).
2. Reinicia Live. En *Preferencias → Link, Tempo y MIDI → Superficie de control* elige **AbletonOSC**.
3. En la barra de estado de Live sale "AbletonOSC: Listening for OSC on port 11000".

Detalles y resolución de problemas en [`ableton/README.md`](ableton/README.md).

## Primer uso

1. Mac e iPad en la misma red (Wi‑Fi del local o, mejor en directo, cable Ethernet entre ambos).
2. Abre StageDeck → **Connect**. En unos segundos aparecen tus pistas, clips y escenas.
3. Si tu set tiene pistas de grupo (p. ej. `A` y `B`), cada grupo es un deck. Si no, un deck con
   todo; puedes definir decks a mano en Ajustes → Decks (por nombre de pista).
4. Grupos de lanzamiento: StageDeck crea **K** (pistas con "kick", "bass", "lo", "sub") y **R**
   (el resto) si los detecta; edítalos en Ajustes → Launch groups.
5. Mantén pulsado un clip para escribir una nota (letra, "subir filtro", tonalidad…).
6. Para el filtro por pista en el mixer, pon un **Auto Filter** en cada pista (y en la pista de
   grupo para el HPF de deck). StageDeck lo detecta por nombre de clase y mueve su *Frequency*.
7. Controlador (CTRL): pulsa EDIT → ADD, elige el tipo, y en el editor asigna el control a un parámetro de Live (con "Use the device selected in Live" te ahorra buscarlo) o a un CC MIDI (luego MIDI Map en Live). Las páginas se guardan con tu perfil.
8. Secuenciador: Ajustes → MIDI → activa el destino (Network Session, Bluetooth, USB). En Live crea
   una pista MIDI con entrada "Network Session 1" (o el puerto que uses), canal según la pista del
   secuenciador. Por defecto el secuenciador sigue el play/stop y el tempo de Live.

## Con hardware, con instrumentos de Live, o improvisando

* **Hardware**: cada pista del secuenciador elige puerto MIDI (USB, Bluetooth, red, o "todos") y
  canal; clock MIDI y Start/Stop configurables (y a qué puerto van); program change por pista al
  arrancar un patrón; lanes de CC con nombre y valor por defecto; compensación de latencia por
  puerto en Ajustes → MIDI (por ejemplo −15 ms para Bluetooth); los puertos elegidos se recuerdan.
  La app también puede esclavizarse a clock externo (SEQ → MIDI Clock In) o funcionar sola sin
  Live. Plantilla incluida "Hardware: acid + drums" como punto de partida.
* **Instrumentos de Live**: el secuenciador llega a cualquier pista MIDI de Live por Network MIDI,
  Bluetooth o cable (IDAM). SEQ → TOOLS → **Send to Live** vuelca el patrón actual (o todas las
  pistas, por nombre) a un clip MIDI de la pista y escena que elijas, con condiciones,
  probabilidad, retrigs, swing y micro‑timing ya convertidos en notas; eliges cuántos compases.
* **Improvisación**: teclado en escala y pads con grabación en vivo cuantizada, FILL, mute/solo por
  pista, cola de patrones, euclid y random al vuelo, páginas CTRL con XY y botones, y nada que
  dependa de un set preparado: el secuenciador y las páginas CTRL funcionan sin Live.

## Estructura del proyecto

```
StageDeck.xcodeproj         Proyecto Xcode (carpeta sincronizada: añade archivos y ya están en el target)
StageDeck/
  App/                      Punto de entrada
  Core/                     Lógica independiente de plataforma (se compila y testea en Linux/CI)
    OSC/                    Codificador/decodificador OSC 1.0
    Ableton/                Modelo del set, protocolo AbletonOSC, secciones, decks, grupos, dB
    Sequencer/              Modelo y motor del secuenciador, escalas, euclídeo
    MIDI/                   Mensajes MIDI
    Profile/                Perfil del performer (todo lo configurable) y persistencia JSON
  Services/                 CoreMIDI, cliente OSC (Network.framework + broadcast), sesión con Live,
                            runtime del secuenciador (hilo de alta prioridad), almacén
  Views/                    SwiftUI: Launcher, Mixer, Sequencer, Settings, componentes
Tests/StageDeckCoreTests/   33 tests del núcleo (swift test)
ableton/AbletonOSC/         Remote script para Live (MIT) + extensión master/retornos
docs/                       Investigación, arquitectura
```

### Tests del núcleo sin Xcode

```bash
swift test      # Linux o macOS: OSC, protocolo, secciones, motor del secuenciador
```

## Estado

Versión 0.1 (uso personal, primera beta). Probado: núcleo con tests automáticos; la app completa
compila contra la API de SwiftUI/Network/CoreMIDI según se ha podido verificar fuera de Xcode.
Lo que conviene probar primero en el iPad real, por orden: conexión y carga del set, lanzar clips,
faders del mixer, secuenciador contra una pista MIDI de Live, y después hardware.

Hoja de ruta en [`docs/RESEARCH.md`](docs/RESEARCH.md) (lo que la gente pide en foros y lo que falta).
