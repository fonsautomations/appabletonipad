# Arquitectura

## Capas

```
Views (SwiftUI)  ──▶  Services (@MainActor)  ──▶  Core (puro, testeable)
 Launcher/Mixer/Seq     LiveSession, SequencerRuntime,   OSCMessage, LiveProtocol, LiveModel,
 Settings               MIDIService, OSCClient, AppStore  SequencerEngine, Scales, Profile
```

* **Core** no importa nada de Apple salvo Foundation. Se compila como paquete Swift
  (`Package.swift`) para ejecutar los tests en Linux/CI y se incluye tal cual en el target de la
  app (carpeta sincronizada de Xcode 16).
* **Services** contienen todo lo que toca sistema: CoreMIDI, Network.framework, sockets BSD para
  broadcast, timers y persistencia.
* **Views** sólo leen estado publicado y llaman a métodos de los servicios.

## Flujo con Live

1. `LiveSession.connect()` abre el listener UDP en 11001 y manda `/live/test` (al host configurado
   o por broadcast a todas las interfaces). La respuesta revela la IP del Mac.
2. `loadSession()` pide número de pistas/escenas, tempo, cuantización, nombres de escena, retornos
   y, con `/live/song/get/track_data`, nombre/color/grupo/mute/solo/slot de todas las pistas en un
   mensaje. Por pista pide clips (nombre, color, longitud en bloque), dispositivos y envíos.
3. `startListeners()` registra listeners: tempo, play, beat, cuantización, master; por pista:
   playing/fired slot, volumen, mute, solo, nombre, color, arm y vúmetro. Cuando una pista cambia
   de clip en reproducción, se escucha `playing_position` sólo de ese clip.
4. Los eventos entran por `LiveEventDecoder` (tipados y testeados) y se aplican a `LiveSongState`
   en el hilo principal. Vúmetros y posiciones van a `LiveMeters` y se publican a 20 Hz para que la
   rejilla no se redibuje con cada paquete.
5. Los faders usan `sendThrottled` (un mensaje por control cada 30 ms, siempre el último valor).

Extensión propia del lado de Live (`ableton/AbletonOSC/abletonosc/master.py`): master volume,
cue volume, vúmetro master, número y nombres de retornos, volumen/mute de retornos.

## Secuenciador

* Tiempo en *ticks* (96 por negra, 24 por semicorchea). El motor (`SequencerEngine`) es
  determinista: `render(from:to:)` devuelve eventos con tick absoluto; no sabe de relojes.
* El motor procesa pasos "nominales" con un horizonte de `microRange` ticks por delante para que el
  micro‑timing negativo nunca llegue tarde; los note‑off, retrigs y eventos futuros viven en una
  lista diferida que se vacía por rangos.
* Cambios de patrón (cola, cadena, canción) ocurren exactamente en el límite del ciclo
  (`masterLength`); los contadores de loop por pista sobreviven al ciclo para las condiciones
  `n:m`.
* `SequencerCore` (no aislado a ningún actor, con `NSLock`) corre un `DispatchSourceTimer` de 5 ms
  en una cola `userInteractive`, renderiza 60 ms por delante y envía por CoreMIDI con marcas de
  tiempo `mach_absolute_time` (el driver las respeta: USB, red y Bluetooth). `TickClock` convierte
  tick ↔ segundos con un ancla, así los cambios de tempo no saltan.
* Clock externo: cada 0xF8 avanza 4 ticks; el tempo se estima con media móvil y los eventos del
  tramo se marcan relativos al pulso recibido.
* La UI lee la posición a 30 Hz y sólo publica cuando cambia el paso.

## Páginas de control

`ControlPage` / `ControlWidget` / `ControlTarget` viven en Core (`Profile/ControlPage.swift`). Un
target de Live se guarda por nombre de pista, dispositivo y parámetro con índices de respaldo;
`ControlResolver` lo resuelve contra el set actual. `ControlRuntime` (servicio) envía por OSC
(`setDeviceParameter`, con listener de feedback) o por MIDI (`MIDIService.send`), y mantiene los
valores de los controles MIDI. `ControlLayout.rows` empaqueta los widgets en filas de 8 unidades.

## Persistencia

Un único JSON (`Documents/stagedeck.json`) con `PerformerProfile` (todo lo configurable, notas de
clips, decks, grupos) y `SeqProject` (patrones, cadena, canción). Se guarda con *debounce*.

## Cómo añadir cosas

* Nuevo mensaje de Live: añadir el caso en `LiveEvent`, su parseo en `LiveEventDecoder`, el
  comando en `LiveCommand`, un test en `OSCTests`, y la reacción en `LiveSession.handle`.
* Nuevo parámetro de paso: campo en `Step` (Codable con valor por defecto), uso en
  `SequencerEngine.emitTrig`, test en `SequencerTests`, control en `StepEditor`.
