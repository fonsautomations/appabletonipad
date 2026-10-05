# Instrucciones para una IA: crear plantillas `.stagedeck` a partir de un set de Ableton

Pega este documento entero en el chat de la IA (ChatGPT, Claude, Gemini…) junto con **una** de estas dos cosas:

- **Opción A (recomendada):** el texto que copia StageDeck en *Ajustes → Templates → Copy my set description*. Contiene los nombres reales de pistas, grupos, dispositivos, macros y retornos tal y como los ve la app.
- **Opción B:** el archivo `.als` del set (si la IA puede abrir archivos) o el XML descomprimido. Un `.als` es XML comprimido con gzip: `gunzip -c "Mi set.als" > set.xml`.

Después pide lo que quieras, por ejemplo: *"Hazme una plantilla para tocar en directo: una página LIVE con las macros de energía de cada grupo, una página por grupo con las macros de sus stems, decks por grupo y el master como bus."*

El resultado debe ser **un único JSON** válido que yo pegaré en *Ajustes → Templates → Paste template JSON* o guardaré como `nombre.stagedeck`.

---

## 1. Qué es StageDeck y qué hace una plantilla

StageDeck es una app de iPad que controla Ableton Live por OSC (AbletonOSC). Tiene cuatro pantallas: **LAUNCH** (clips por decks), **MIXER** (faders, envíos, filtro por canal, buses), **CTRL** (páginas de knobs, faders, botones y XY que mueven parámetros de Live o mandan MIDI) y **SEQ** (secuenciador).

Una plantilla describe, por **nombre**, qué pistas forman cada deck, qué parámetros de Live mueve cada control, qué canales extra ve el mixer y cómo se llaman las cosas. La app resuelve los nombres contra el set cargado: si un nombre no existe, ese control queda marcado en amarillo (no rompe nada). Por eso **los nombres tienen que ser exactamente los de Live** (mayúsculas, espacios, acentos y símbolos incluidos).

## 2. Cómo leer un `.als` (opción B)

Dentro de `<Ableton><LiveSet>`:

- **Pistas:** `<Tracks>` contiene `<AudioTrack>`, `<MidiTrack>`, `<GroupTrack>` y `<ReturnTrack>`, en el orden de la sesión.
  - Nombre: `Name/EffectiveName Value="…"`.
  - Grupo al que pertenece: `TrackGroupId Value="…"` (el `Id` del `GroupTrack`; `-1` = nivel superior). Un `GroupTrack` puede estar dentro de otro.
  - Color: `Color Value="n"` (índice de la paleta de Live).
- **Dispositivos de una pista:** `DeviceChain/DeviceChain/Devices/<Dispositivo>`. Los racks son `AudioEffectGroupDevice`, `InstrumentGroupDevice`, `MidiEffectGroupDevice`, `DrumGroupDevice`. Su nombre visible es `UserName Value="…"` (si está vacío, el nombre por defecto: "Audio Effect Rack", "Auto Filter", "EQ Eight"…). **Ignora los dispositivos anidados dentro de `Branches`**: la app solo ve los de primer nivel de cada pista.
- **Macros de un rack:** `MacroDisplayNames.0` … `MacroDisplayNames.15` (`Value`). Las que siguen llamándose "Macro 1", "Macro 2"… no se usan en Live y conviene ignorarlas. La macro N es el parámetro N (el parámetro 0 de todo dispositivo es "Device On").
- **Auto Filter:** elemento `<AutoFilter>`; su parámetro de corte se llama "Frequency". La app lo usa para el filtro de los strips del mixer y el HPF de cada deck (si está en la pista de grupo).
- **Retornos:** `<ReturnTrack>` con su `EffectiveName` (por ejemplo "A-A · CINTA").
- **Master:** `<MainTrack>` (o `<MasterTrack>` en versiones antiguas); sus dispositivos en `MainTrack/DeviceChain/DeviceChain/Devices`. El master **no tiene envíos**.
- **Tempo:** `MainTrack/DeviceChain/Mixer/Tempo/Manual Value`.
- **Escenas:** `<Scenes><Scene><Name Value="…"/>`.

Si hay dos pistas con el mismo nombre, la app coge la primera; avísame y propón renombrar la segunda.

## 3. Formato del JSON

Cabecera obligatoria y secciones, todas opcionales:

```json
{
  "format": "stagedeck-template",
  "version": 1,
  "name": "Nombre de la plantilla",
  "author": "quien la hace",
  "description": "qué contiene y para qué",
  "decks": [],
  "launchGroups": [],
  "controlPages": [],
  "mixerBuses": [],
  "trackAliases": {},
  "clipNotes": {},
  "layout": {}
}
```

Todos los `id` son UUID (cualquiera válido; la app genera nuevos al importar). Colores en hex `#RRGGBB`.

### `decks` (LAUNCH y MIXER)

Un deck por grupo de nivel superior es lo normal. O refleja un grupo (`groupTrackName`, y `trackNames` vacío) o lista pistas sueltas (`trackNames`).

```json
"decks": [
  { "id": "00000000-0000-4000-8000-000000000001", "name": "01 PULSO", "groupTrackName": "01 PULSO", "trackNames": [], "colorHex": "#FF3636" },
  { "id": "00000000-0000-4000-8000-000000000002", "name": "EXTRAS", "trackNames": ["REC XONE", "DRONE"], "colorHex": "#8FB4DD" }
]
```

### `launchGroups` (botones K / R en el launcher)

Disparan una fila solo en las pistas listadas. Útil para "solo percusión" / "solo melódico".

```json
"launchGroups": [
  { "id": "00000000-0000-4000-8000-000000000011", "label": "K", "trackNames": ["KICK", "SD", "CLAP"], "colorHex": "#F28C28" }
]
```

### `controlPages` (CTRL)

Cada página tiene `widgets`. La página mide **8 unidades de ancho**; `width` 1‑8. Los controles se colocan en orden, saltando de fila cuando no caben, así que **una fila = controles cuyos anchos suman 8**.

`kind`: `knob` (continuo), `fader` (continuo, alto), `button` (momentáneo: manda máximo al pulsar y mínimo al soltar), `toggle` (alterna mínimo/máximo), `xy` (dos parámetros, `target` y `targetY`).

`target` (y `targetY` solo en `xy`):

- Parámetro de Live: `{"liveParameter": {"track": "01 PULSO", "trackIndex": -1, "device": "ENERGIA subir y soltar", "deviceIndex": -1, "parameter": "Energía", "parameterIndex": -1}}`. Usa `-1` en los índices: la app resuelve por nombre y los rellena. `track` puede ser una pista, una pista de grupo o un retorno; `device` es el nombre visible del dispositivo; `parameter` el nombre de la macro o parámetro.
- CC MIDI a hardware o a Live por MIDI Map: `{"midiCC": {"channel": 0, "controller": 20, "port": {"rawValue": "all"}}}` (canal 0‑15).
- Nota MIDI (en `button`/`toggle`): `{"midiNote": {"channel": 0, "note": 36, "port": {"rawValue": "all"}}}`.
- Sin asignar: `{"none": {}}`.

`minimum`/`maximum` (0‑1) acotan el rango. `value` es el valor inicial (0.5 para knobs que arrancan al centro, 0 para envíos y efectos).

```json
"controlPages": [
  { "id": "00000000-0000-4000-8000-000000000021", "name": "LIVE", "widgets": [
    { "id": "00000000-0000-4000-8000-000000000101", "name": "01 PULSO", "kind": "fader", "colorHex": "#FF3636", "width": 2,
      "target": { "liveParameter": { "track": "01 PULSO", "trackIndex": -1, "device": "ENERGIA subir y soltar", "deviceIndex": -1, "parameter": "Energía", "parameterIndex": -1 } },
      "targetY": { "none": {} }, "minimum": 0, "maximum": 1, "value": 0, "valueY": 0 },
    { "id": "00000000-0000-4000-8000-000000000102", "name": "Roll", "kind": "button", "colorHex": "#FF3636", "width": 1,
      "target": { "liveParameter": { "track": "01 PULSO", "trackIndex": -1, "device": "ENERGIA subir y soltar", "deviceIndex": -1, "parameter": "Roll", "parameterIndex": -1 } },
      "targetY": { "none": {} }, "minimum": 0, "maximum": 1, "value": 0, "valueY": 0 }
  ] }
]
```

### `mixerBuses` (canales extra del mixer)

`kind`: `group`, `returnTrack`, `track` o `master`. `name` = nombre en Live (se ignora en `master`). Opcionales: `label`, `showSends` (true), `showFilter` (true), `showPan` (false).

```json
"mixerBuses": [
  { "kind": "master", "label": "MASTER", "showSends": false },
  { "kind": "returnTrack", "name": "A-A · CINTA", "label": "CINTA" }
]
```

### `trackAliases` (nombres que se ven en la app)

```json
"trackAliases": { "SYNTRX II": "SYNTRX", "A-A · CINTA": "CINTA" }
```

### `clipNotes` (texto dentro de un clip)

Clave `"<pista>|<nombre del clip>"`: `{"BASS|intro-bass": "subir filtro aquí"}`.

### `layout`

Opcionales: `showGroupStrips` (cada deck enseña su grupo como strip), `showMasterFilter`, `showSends`, `showPan`, `visibleSends` (nombres de retorno cuyos envíos se ven), `clipHeight` (36‑110), `clipFontSize` (9‑20), `showClipNotes`, `showSceneButtons`, `showStopButtons`, `showCueButtons`, `hideEmptyScenes`, `bigTextMode`.

## 4. Reglas de diseño para una plantilla de directo

1. **Página LIVE primero:** una fila por grupo de nivel superior, con el color del grupo. Primer control de la fila: fader ancho (width 2) con el nombre del grupo apuntando a su macro principal (energía, filtro…). Resto de la fila: las macros del grupo que cambian el directo (soltar, roll, silencio, filtro, drive…). Sumar 8 por fila.
2. **Una página por grupo:** arriba la fila del grupo; debajo, por cada stem, sus macros con nombre propio (hasta 8, en el orden del rack), coloreadas con el color de la pista. Pon el nombre de la pista en el primer control de cada stem ("KICK · Boom") y solo el nombre de la macro en los demás.
3. **Macros que son interruptores** (roll, mute, freeze, silencio): `button` si es momentáneo, `toggle` si se queda. Las demás, `knob`. Los envíos y volúmenes, `fader`.
4. **No repitas** la misma macro en varias páginas salvo en LIVE; no metas macros de utilidad (EQ, limitador, "Device On").
5. **Decks:** uno por grupo de nivel superior, mismo color que el grupo. **Buses:** el master y los retornos que se tocan en directo. `showGroupStrips: true` si los grupos tienen macros de mezcla.
6. **Nombres cortos** en los controles (una palabra o dos): la etiqueta se corta a una línea.
7. **Lo que no exista en el set no lo inventes.** Si dudas de un nombre, pregúntame.
8. Antes de entregar, comprueba: JSON válido, todos los `id` distintos, cada `liveParameter` con `track`/`device`/`parameter` que existan, y que cada fila de cada página sume 8 de ancho (o menos en la última).

## 5. Entrega

Devuélveme solo el JSON (sin comentarios ni texto dentro del JSON) y, aparte, una lista de dudas: nombres repetidos, racks sin macros con nombre, grupos sin Auto Filter (si quiero HPF por deck, la app lo necesita en la pista de grupo).
