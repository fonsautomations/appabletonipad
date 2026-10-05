# Formato de plantillas `.stagedeck`

Una plantilla es un archivo JSON (extensión `.stagedeck`, también se acepta `.json` o texto
pegado) que StageDeck importa desde Archivos, AirDrop, cualquier app que comparta archivos, o
pegando el texto en *Ajustes → Templates → Paste template JSON*. Al importar, la app muestra qué
contiene, qué pistas y dispositivos espera y cuáles faltan en tu set, y deja elegir entre
**añadir** o **sustituir** cada sección. Nunca se importan ajustes de conexión.

Todas las secciones son opcionales. Una plantilla con sólo `trackAliases` es válida.

## Cabecera

```json
{
  "format": "stagedeck-template",
  "version": 1,
  "name": "Mi directo 2026",
  "author": "Jorge",
  "description": "Dos decks, macros del rack principal y nombres en castellano.",
  "requires": { "tracks": ["KICK", "SYN-1"], "devices": ["SYN-1/Main Rack"] }
}
```

`requires` es informativo: la app lo usa para avisar de lo que falta.

## Secciones

### `trackAliases` — nombres de canal

Nombre de pista en Live → nombre que quieres ver en launcher, mixer y controles.

```json
"trackAliases": { "KICK": "BOMBO", "LO": "BAJO", "HI PERC": "PERC AGUDA" }
```

### `decks` — decks del launcher

Un deck muestra un subconjunto de pistas. O refleja un grupo de Live (`groupTrackName`) o lista
pistas por nombre (`trackNames`). `colorHex` es el color del deck.

```json
"decks": [
  { "id": "6E9B8C5A-1111-4F5B-9C3A-000000000001", "name": "A", "trackNames": [], "groupTrackName": "A", "colorHex": "#F28C28" },
  { "id": "6E9B8C5A-1111-4F5B-9C3A-000000000002", "name": "B", "trackNames": ["KICK B", "BASS B", "LEAD B"], "colorHex": "#8FB4DD" }
]
```

### `launchGroups` — botones K / R

Disparan una fila (escena) sólo en las pistas listadas.

```json
"launchGroups": [
  { "id": "6E9B8C5A-2222-4F5B-9C3A-000000000001", "label": "K", "trackNames": ["KICK", "LO"], "colorHex": "#F28C28" },
  { "id": "6E9B8C5A-2222-4F5B-9C3A-000000000002", "label": "R", "trackNames": ["HI PERC", "SYN-1", "FX"], "colorHex": "#C8762A" }
]
```

### `controlPages` — páginas de controles (CTRL)

Cada página tiene `widgets`. `kind` es `fader`, `knob`, `button`, `toggle` o `xy`. `width` va de
1 a 8 (la página tiene 8 unidades de ancho). `target` (y `targetY` en los XY) es una de:

* Parámetro de Live por OSC, con feedback:
  `{"liveParameter": {"track": "SYN-1", "trackIndex": 5, "device": "Main Rack", "deviceIndex": 1, "parameter": "Macro 1", "parameterIndex": 1}}`
  Los índices son respaldo; se busca primero por nombre.
* CC MIDI (canal 0‑15, es decir canal 1 = 0): `{"midiCC": {"channel": 0, "controller": 20, "port": {"rawValue": "all"}}}`
* Nota MIDI (botones y toggles): `{"midiNote": {"channel": 0, "note": 60, "port": {"rawValue": "all"}}}`
* Sin asignar: `{"none": {}}`

`minimum` y `maximum` (0‑1) acotan el rango que manda el control.

```json
"controlPages": [
  {
    "id": "6E9B8C5A-3333-4F5B-9C3A-000000000001",
    "name": "Drop",
    "widgets": [
      { "id": "6E9B8C5A-4444-4F5B-9C3A-000000000001", "name": "Filtro lead", "kind": "knob", "colorHex": "#9A6BFF", "width": 1,
        "target": { "liveParameter": { "track": "SYN-1", "trackIndex": 5, "device": "Main Rack", "deviceIndex": 1, "parameter": "Macro 1", "parameterIndex": 1 } },
        "targetY": { "none": {} }, "minimum": 0, "maximum": 1, "value": 0.5, "valueY": 0 },
      { "id": "6E9B8C5A-4444-4F5B-9C3A-000000000002", "name": "Riser", "kind": "fader", "colorHex": "#F2D33C", "width": 1,
        "target": { "midiCC": { "channel": 0, "controller": 21, "port": { "rawValue": "all" } } },
        "targetY": { "none": {} }, "minimum": 0, "maximum": 1, "value": 0, "valueY": 0 },
      { "id": "6E9B8C5A-4444-4F5B-9C3A-000000000003", "name": "FX", "kind": "xy", "colorHex": "#E05A9A", "width": 2,
        "target": { "midiCC": { "channel": 0, "controller": 30, "port": { "rawValue": "all" } } },
        "targetY": { "midiCC": { "channel": 0, "controller": 31, "port": { "rawValue": "all" } } },
        "minimum": 0, "maximum": 1, "value": 0.5, "valueY": 0.5 },
      { "id": "6E9B8C5A-4444-4F5B-9C3A-000000000004", "name": "Stutter", "kind": "button", "colorHex": "#F28C28", "width": 1,
        "target": { "midiNote": { "channel": 0, "note": 36, "port": { "rawValue": "all" } } },
        "targetY": { "none": {} }, "minimum": 0, "maximum": 1, "value": 0, "valueY": 0 }
    ]
  }
]
```

Los `id` deben ser UUID (cualquier UUID válido; la app genera nuevos al importar).

### `clipNotes` — notas dentro de los clips

Clave `"<nombre de pista>|<nombre de clip>"`.

```json
"clipNotes": { "LO|basilar_5-LO": "drop aquí", "FX|perpenar_1-FX": "subir filtro" }
```

### `mixerBuses` — canales extra del mixer

Cada bus es un canal propio (fader, envíos, filtro y mute) para un grupo, un retorno, el master o
cualquier pista. Se muestran entre los decks y el master, en el orden de la lista. `kind` es
`group`, `returnTrack`, `master` o `track`; `name` es el nombre en Live (se ignora para `master`).

```json
"mixerBuses": [
  { "kind": "group", "name": "01 PULSO" },
  { "kind": "returnTrack", "name": "A-A · CINTA", "showFilter": false },
  { "kind": "master", "label": "OUT" }
]
```

Opcionales por bus: `label` (texto que se ve en vez del nombre), `showSends` (true), `showFilter` (true),
`showPan` (false). El master de Live no tiene envíos; su strip muestra fader y el Auto Filter que
tenga puesto el master.

### `layout` — ajustes de launcher y mixer

Todos opcionales: `clipHeight` (36‑110), `clipFontSize` (9‑20), `showClipProgress`, `showTrackMeters`,
`showClipNotes`, `showSceneButtons`, `showStopButtons`, `showCueButtons`, `showSections`,
`bigTextMode`, `dimStoppedClips`, `hideEmptyScenes`, `showSends`, `showPan`, `filterParameterName`,
`showGroupStrips` (cada deck enseña su pista de grupo como strip completo), `showMasterFilter`,
`visibleSends` (lista de nombres de retorno cuyos envíos se ven en los strips; sin ella, los 4 primeros).

### `patterns` y `sequencer` — secuenciador

`patterns` es una lista de patrones con el mismo formato que guarda la app (`name`, `masterLength`,
`swing`, `tracks[]` con `name`, `channel` 0‑15, `defaultNote`, `length`, `speed` (`"2x"`, `"3/2x"`,
`"1x"`, `"3/4x"`, `"1/2x"`, `"1/4x"`, `"1/8x"`), `direction`, `steps[]` de 64 pasos). Un paso:

```json
{ "isOn": true, "notes": [36], "velocity": 110, "length": 0.5, "micro": 0, "probability": 100,
  "condition": { "always": {} }, "retrig": { "count": 1, "rateTicks": 6, "velocityRamp": 0 },
  "locks": {}, "accent": false, "slide": false, "programChange": -1 }
```

Condiciones: `{"always":{}}`, `{"ratio":{"n":1,"of":2}}`, `{"fill":{}}`, `{"notFill":{}}`,
`{"first":{}}`, `{"notFirst":{}}`, `{"pre":{}}`, `{"notPre":{}}`, `{"neighbor":{}}`, `{"notNeighbor":{}}`.
`locks` es `{"74": 100}` (número de CC → valor).

`sequencer`: `tempo`, `rootNote` (0‑11), `scaleName`, `arrangeMode` (`pattern`, `chain`, `song`),
`chain` (índices), `song` (`[{"patternIndex":0,"repeats":4}]`).

La forma más fácil de obtener un patrón completo es exportarlo desde la app y editarlo.

## Pedírselo a una IA

1. En la app: *Ajustes → Templates → Copy my set description*. Eso copia un texto con tus pistas,
   grupos, dispositivos y nombres de parámetros reales.
2. Pega en el chat ese texto, este documento, y lo que quieres: "hazme una página de control
   'Drop' con las 8 macros del rack de SYN-1 y un XY para el delay de FX, y nombres de canal en
   castellano".
3. Copia el JSON que te devuelva y pégalo en *Ajustes → Templates → Paste template JSON*. La app
   lo valida (si falta algo, dice qué) y te enseña qué pistas no existen antes de importar.
