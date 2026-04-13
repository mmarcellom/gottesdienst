# Tertius Streaming-Setup — Migration Plan

**Stand:** 2026-04-07
**Ziel:** Aufbau-Zeit halbieren, Bedienung auf eine Person reduzieren, Aushilfen-tauglich machen.
**Risiko-Level:** Niedrig — altes Setup bleibt als Backup voll funktionsfähig.

---

## 0. Mini-Glossar (für alle, die nicht aus der Technik kommen)

| Wort | Was es einfach bedeutet |
|---|---|
| **Switch / Netzwerk-Switch** | Ein kleines Kästchen mit mehreren LAN-Buchsen — wie eine Steckdosenleiste, nur für Netzwerkkabel. Verbindet Geräte miteinander. **Haben wir schon im Saal.** |
| **RJ45 / LAN / Ethernet** | Das ist ein **normales Netzwerkkabel** (sieht aus wie ein dickeres Telefonkabel). |
| **RTSP** | Eine technische Sprache, mit der Kameras ihr Live-Bild übers Netzwerk verschicken. Wir nutzen sie, damit OBS direkt das Bild der PTZ-Kameras sieht. |
| **OBS** | Kostenlose Software auf dem Mac Mini, die das Bild der Kameras + den Ton zusammenbaut und zu YouTube schickt. **Quasi die neue Stream-Zentrale.** |
| **Multi-RTMP** | Eine Erweiterung für OBS, die zwei YouTube-Streams gleichzeitig (deutsch + russisch) rausschickt. |
| **PTZ-Kamera** | Schwenk-/Zoom-Kamera, die wir vom Mischplatz aus bewegen können — die zwei haben wir schon. |
| **X32 Rack** | Unser Audio-Mischpult, an dem alle Mikros hängen. **Bleibt unverändert.** |
| **X-USB** | Eine eingebaute Funktion im X32, mit der **ein einziges USB-Kabel** alle 32 Audiokanäle zum Mac Mini überträgt. |
| **Stream Deck +** | Das Bedienpult mit den leuchtenden Knöpfen + Drehreglern. **Haben wir schon, wird einfach um neue Knöpfe ergänzt.** |
| **Elgato Key Light** | Eine sehr helle, dimmbare LED-Flächenleuchte für Bühne / Pastor. Wird per WLAN gesteuert. **Haben wir 2 Stück, hängen heute schon am Stream Deck.** |

---

## 1. Hardware-Inventar

### Bleibt unverändert
| Gerät | Funktion | Warum bleibt |
|---|---|---|
| **X32 Rack** | Audio-Mischpult, Beschallung Saal/MuKi/Übersetzer-IEM | Herzstück, X-USB ab Werk drin → eine USB-Verbindung reicht für 32 Kanäle zum Mac |
| **SD8** | Stagebox am Mischplatz, Übersetzer-Funkempfang | Übersetzer-Mikro hängt schon dort, AES50 zum X32 läuft |
| **2× SMTAV PTZ 30x** | Front + Seitenkamera | RTSP/IP schon verkabelt, perfekt für OBS |
| **Mac Mini M1 16GB** | Wird zur Stream-Zentrale | M1 packt 2× 1080p Encode + Whisper lokal locker |
| **Stream Deck +** | Bedien-Konsole | Wird einfach um OBS-Tasten erweitert |
| **Netzwerk-Switch** (= LAN-Verteiler, vorhandenes Kästchen mit mehreren Netzwerk-Buchsen) | Verbindet die PTZ-Kameras und den Mac Mini per Netzwerkkabel miteinander | Schon vorhanden — die Kameras hängen heute schon dran, weil das Stream Deck sie darüber steuert |
| **2× Elgato Key Light** | Beleuchtung für Pastor / Bühne, dimmbar &amp; per Netzwerk steuerbar | Schon vorhanden, hängen schon im Stream Deck — werden in der neuen Lösung sauber als Szenen-Presets eingebunden |

### Wird ausgebaut (nach erfolgreicher Probe)
| Gerät | War für | Warum raus |
|---|---|---|
| **RØDECaster Video** | Kamera-Mix vor OBS | OBS macht das direkt aus den IP-Streams |
| **Blackmagic Streaming Encoder HD** | Separater RU-Stream | OBS streamt beide Sprachen parallel via Multi-RTMP |

**Geschätzter Restwert** (Verkauf):
- RØDECaster Video: ~700–900 EUR gebraucht
- Blackmagic Streaming Encoder HD: ~300–400 EUR gebraucht
- **= ~1.000–1.300 EUR** kommen wieder rein

### Wird neu installiert (Software)
| Software | Zweck | Lizenz |
|---|---|---|
| **OBS Studio** (am Mac Mini, vermutlich schon da) | Aufnahme + Encoding + Streaming | Kostenlos |
| **OBS Multi-RTMP Plugin** | Parallel zu 2 YouTube-Kanälen pushen | Kostenlos |
| **obs-websocket** (Plugin, ab OBS 28 mitgeliefert) | Steuerung von außen (Stream Deck, später iPad-App) | Kostenlos |
| **Stream Deck OBS Plugin** | Knöpfe für OBS-Aktionen | Kostenlos |
| **PTZ.OBS Plugin** (optional) | PTZ-Joystick + Presets in OBS-Sidebar | Kostenlos |

---

## 2. Verkabelung — Vorher / Nachher

### Vorher
```
PTZ Front  ──HDMI──┐
                   ├─> RØDECaster Video ──HDMI──> Mac Mini ──> OBS ──> YouTube DE
PTZ Seite  ──HDMI──┘                  └────────> Blackmagic Encoder ──> YouTube RU
                                                  ▲
PTZ Front  ──RJ45──┐                              │
                   ├─> Switch ──> Stream Deck +   │
PTZ Seite  ──RJ45──┘            (PTZ-Steuerung)   │
                                                  │
Übersetzer-Mikro ──Funk──> SD8 ──XLR Direct──────┘
                            │
                            └─AES50──> X32 Rack ──XLR Outs──> Saal-PA, MuKi-LS, IEMs
                                          │
                                          └─USB Stereo──> Mac Mini ──> OBS (DE-Mix)
```
**Pfade:** 4 separate Signal-Wege, 2 Encoder, 5 Geräte aktiv.

### Nachher
```
PTZ Front  ──Netzwerkkabel──┐
                            ├─> Netzwerk-Switch ──┐
PTZ Seite  ──Netzwerkkabel──┘   (LAN-Verteiler)   │
                                │
Übersetzer-Mikro ──Funk──> SD8  │
                            │   │
                            └─AES50──> X32 Rack ──XLR Outs──> Saal-PA, MuKi-LS, IEMs
                                          │     │
                                          │     └─USB-B (32ch)──> Mac Mini
                                          │                          │
                                          │                          ▼
                                          │                  ┌──────────────┐
                                          └──────────────────┤  OBS Studio  │
                                          (Switch über LAN)  │  + Multi-RTMP│
                                                             │  + websocket │
                                                             └──────┬───────┘
                                                                    │
                                                          ┌─────────┴─────────┐
                                                          │                   │
                                                          ▼                   ▼
                                                    YouTube DE          YouTube RU
                                                    (Track 1)           (Track 2)

Stream Deck + ──USB──> Mac Mini (steuert OBS + PTZ-Presets)
```
**Pfade:** 1 OBS-Instanz, 2 Geräte aktiv (X32 + Mac Mini), Stream Deck als Bedienoberfläche.

---

## 3. X32 Routing — was im X32 Edit eingestellt werden muss

**Ziel:** DE-Mix und RU-Mix gehen als getrennte Spuren über USB zum Mac.

### Schritt 1: Card-Output konfigurieren
1. X32 Edit am Mac öffnen
2. **Routing → Card Out**
3. Folgende Zuordnung setzen:

| USB-Out-Kanal (zum Mac) | Quelle im X32 |
|---|---|
| 1 | Bus 1 L (DE-Mix) |
| 2 | Bus 1 R (DE-Mix) |
| 3 | Bus 2 L (RU-Mix) |
| 4 | Bus 2 R (RU-Mix) |
| 5–32 | (optional: alle Einzelmics für Multitrack-Recording) |

### Schritt 2: Bus 1 = DE-Mix
1. **Mixer → Bus 1**
2. Alle relevanten Eingangskanäle (Pastor, Lobpreisband, etc.) auf Bus 1 senden
3. Bus 1 als **Stereo Bus** konfigurieren
4. Pegel auf saubere -12 dBFS Spitze einstellen

### Schritt 3: Bus 2 = RU-Mix
1. **Mixer → Bus 2**
2. **NUR den Übersetzer-Kanal** (das Funkmikro vom SD8) auf Bus 2 senden
3. Bus 2 ebenfalls Stereo
4. Pegel sauber einstellen

### Schritt 4: Snapshot speichern
1. **Setup → Show Control → Snapshots**
2. Neuer Snapshot: **"Tertius Stream Setup"**
3. Damit kann das Routing per Knopfdruck wiederhergestellt werden falls jemand was verstellt

### Schritt 5: USB-Verbindung Mac
1. **USB-B → USB-A Kabel** (Standard-Druckerkabel) vom X32 Rack zum Mac Mini
2. Am Mac: **Audio-MIDI-Setup** öffnen → "X32" sollte als 32×32 Gerät erscheinen
3. Falls nicht: macOS reboot, manchmal hilfts

---

## 4. PTZ-Kameras in OBS einbinden (RTSP)

### IP-Adressen herausfinden
Die Kameras haben aktuell schon IPs (weil Stream Deck sie steuert). IPs notieren:
- **Front-Kamera**: z.B. `192.168.1.50`
- **Seiten-Kamera**: z.B. `192.168.1.51`

### RTSP-URL pro Kamera
SMTAV PTZ-Kameras nutzen typischerweise dieses URL-Schema:
```
rtsp://<IP>:554/1                    (Hauptstream, höchste Qualität)
rtsp://<IP>:554/2                    (Substream, niedriger)
```
Falls Auth aktiv: `rtsp://username:password@<IP>:554/1`
(Standard-Login bei SMTAV oft `admin/admin`)

**Test der URL** (vor OBS-Einbindung):
```bash
ffplay rtsp://192.168.1.50:554/1
```
Wenn das Bild kommt → URL ist korrekt.

### In OBS einbinden
1. OBS → **Sources → +** → **Media Source**
2. Name: **PTZ Front**
3. **"Local File" abwählen**
4. **Input:** `rtsp://192.168.1.50:554/1`
5. **Input Format:** `rtsp`
6. **Reconnect Delay:** 2 Sekunden (für Stabilität)
7. **Use hardware decoding when available:** ✓ (M1 nutzt VideoToolbox)
8. OK → Source ist da

Gleiches für **PTZ Seite** wiederholen.

### Latenz-Optimierung
RTSP hat typisch 1–3 Sekunden Latenz. Für Live-Stream OK, für Monitoring im Saal ggf. zu viel. Falls Latenz stört:
- Im OBS Source-Properties: **"Restart playback when source becomes active"** aktivieren
- Buffer-Size auf Minimum stellen

---

## 5. OBS Audio-Tracks konfigurieren

**Ziel:** OBS sieht den X32 als Audio-Eingang und routet DE auf Track 1, RU auf Track 2.

### Schritt 1: Audio-Quelle hinzufügen
1. OBS → **Sources → +** → **Audio Input Capture**
2. Name: **X32 USB**
3. Device: **X32** (sollte in Liste erscheinen)
4. OK

### Schritt 2: Audio Mixer konfigurieren
1. Im Audio Mixer (unten in OBS) auf das Zahnrad neben **X32 USB** → **Advanced Audio Properties**
2. Bei **X32 USB**:
   - **Tracks:** Aktiviere **Track 1** und **Track 2** (beide!)
   - **Channels:** Wähle "Mono / Stereo" je nach Bus-Konfig
3. Aber: Wir müssen die Kanäle auf die Tracks **mappen**

### Schritt 3: Channel-Mapping (wichtig!)
Standardmäßig nimmt OBS nur die ersten 2 Kanäle. Wir wollen aber:
- **Track 1 = USB Kanäle 1+2 (DE-Mix vom Bus 1)**
- **Track 2 = USB Kanäle 3+4 (RU-Mix vom Bus 2)**

Das geht so:
1. Lege **zwei** "Audio Input Capture" Sources an, beide zeigen auf X32:
   - **X32 — DE-Mix** → Track 1 only, Channels 1+2
   - **X32 — RU-Mix** → Track 2 only, Channels 3+4
2. macOS routet die Kanäle direkt aus dem Multi-Channel-Device
3. Falls macOS nicht direkt mappen kann: Aggregate Device im **Audio-MIDI-Setup** anlegen (advanced)

**Alternative (einfacher):** Auf dem X32 routest du direkt Bus 1 auf Card-Out 1+2 UND Bus 2 auf Card-Out 1+2 in **zwei verschiedenen X32 Edit Profilen**, die du beim Bedarf wechselst. Aber das ist umständlicher.

**Empfehlung:** Aggregate Device im Audio-MIDI-Setup. Brauche ich beim Vor-Ort-Setup.

### Schritt 4: Output-Settings
1. OBS → **Settings → Output**
2. **Output Mode:** Advanced
3. Tab **Streaming**:
   - **Audio Track:** Track 1
4. Tab **Recording** (für Backup):
   - **Audio Track:** Track 1, 2 (beide aufnehmen)

---

## 6. Multi-RTMP für 2 YouTube-Kanäle

### Plugin installieren
1. Download: https://github.com/sorayuki/obs-multi-rtmp/releases
2. macOS Variante (.pkg)
3. Installieren, OBS neu starten
4. Im OBS unten rechts erscheint ein neues Panel **"Multiple Output"**

### Kanal 1 konfigurieren — DE
1. Im Multi-Output Panel: **Add new target**
2. Name: **YouTube DE**
3. **Server:** `rtmp://a.rtmp.youtube.com/live2`
4. **Stream Key:** Aus YouTube Studio → Live → Stream Key kopieren
5. **Audio Track:** Track 1
6. **Video Encoder:** Apple VT H264 Hardware Encoder (M1)
7. **Bitrate:** 6000 kbps
8. Save

### Kanal 2 konfigurieren — RU
1. **Add new target**
2. Name: **YouTube RU**
3. **Server:** `rtmp://a.rtmp.youtube.com/live2`
4. **Stream Key:** Aus dem RU-Kanal bei YouTube Studio
5. **Audio Track:** Track 2
6. **Video Encoder:** Apple VT H264 Hardware Encoder (M1)
7. **Bitrate:** 6000 kbps
8. Save

### Streamen
- **OBS Settings → Stream → Service: None** (wichtig! Sonst gibt OBS Studio noch einen 3. Stream raus)
- Im Multi-Output Panel: **Start All** drückt beide Streams gleichzeitig

**Vorteil:** Du siehst pro Stream den Status (Bitrate, Verbindung, Frames dropped).

---

## 7. OBS-Szenen — Vorschlag

| Szene | Inhalt | Bedienung |
|---|---|---|
| **Begrüßung** | PTZ Front (Weit), Lower Third "Tertius — Sonntagsgottesdienst", dezente Musik, Key Lights 60% warm | Stream Deck Knopf 1 |
| **Lobpreis** | Cut zwischen Front + Seite, je nach Kamera-Operator | Stream Deck Knopf 2 |
| **Predigt** | Front Close-Up auf Pastor, Lower Third mit Name + Thema, Key Lights 100% warm (Pastor angeleuchtet) | Stream Deck Knopf 3 |

> **Elgato Key Lights als Szenen-Bestandteil:** Über das offizielle **Elgato Control Center Plugin** (kostenlos) lassen sich Helligkeit + Farbtemperatur direkt aus OBS heraus pro Szene umschalten — kein zusätzlicher Tipp am Stream Deck nötig. Beim Szenenwechsel fahren die Lights automatisch auf den hinterlegten Wert.
| **Spende / Bekanntmachung** | Statisches Bild + Musik, Audio bleibt | Stream Deck Knopf 4 |
| **Outro** | Tertius-Logo, Verlinkungen, Outro-Musik | Stream Deck Knopf 5 |
| **Black / Stream Pause** | Schwarzes Bild, Audio gemutet | Stream Deck Knopf 6 |

Jede Szene als OBS-Szene anlegen, Source-Mix zusammenbauen, Stream Deck Plugin verlinkt sie.

---

## 8. Stream Deck + Layout

Das Stream Deck + hat **8 Tasten + 4 Drehencoder + Touch-Strip**. Vorschlag:

### Tasten (oben)
| Position | Funktion |
|---|---|
| 1 | Szene: Begrüßung |
| 2 | Szene: Lobpreis |
| 3 | Szene: Predigt |
| 4 | Szene: Spende |
| 5 | Szene: Outro |
| 6 | Szene: Black |
| 7 | **STREAM START** (rot, leuchtet wenn live) |
| 8 | **STREAM STOP** |

### Drehencoder + Touch-Strip
| Encoder | Funktion |
|---|---|
| 1 | Master-Volume Track 1 (DE) |
| 2 | Master-Volume Track 2 (RU) |
| 3 | PTZ Front Preset wechseln (Weit/Pastor/Band) |
| 4 | PTZ Seite Preset wechseln (Weit/Übersetzer-Bereich) |

### Touch-Strip (Anzeige)
- Live-Status pro Kanal (DE / RU Bitrate, Frames Dropped)
- Audio-Pegel als Live-Bargraph
- "Übersetzer aktiv" Indikator

**Plugin:** Elgato Stream Deck App → OBS Plugin (kostenlos im Marketplace).

---

## 9. Probe-Stream-Checkliste

**Vor dem ersten echten Sonntag IMMER einen Probe-Stream machen!**

### Vorbereitung (vorabends oder samstags)
- [ ] Mac Mini hochfahren, OBS startet
- [ ] X32 Rack hochfahren, "Tertius Stream Setup" Snapshot laden
- [ ] PTZ-Kameras hochfahren, mit Stream Deck Presets prüfen
- [ ] OBS prüfen: beide PTZ-Quellen liefern Bild
- [ ] OBS prüfen: Audio-Mixer zeigt **2 Tracks aktiv** (DE + RU pegeln)
- [ ] Stream Deck zeigt korrekte Tasten

### Probe-Stream (privat!)
- [ ] In YouTube Studio: **2 private Test-Streams** erstellen (Sichtbarkeit: Privat)
- [ ] Stream-Keys ins Multi-RTMP Plugin kopieren
- [ ] **Start All** drücken
- [ ] Mit zweitem Gerät (Handy) auf YouTube Studio schauen → beide Streams müssen ankommen
- [ ] Audio prüfen: DE-Stream → Hauptmix hörbar, RU-Stream → nur Übersetzer
- [ ] Min. 30 Min stabil laufen lassen
- [ ] Verschiedene Szenen wechseln, schauen ob Stream weiter läuft
- [ ] Pegel-Spitzen prüfen: nichts darf clippen

### Notfall-Fallback im Probe-Test
- [ ] Falls Stream abreißt: Old Setup wieder aktivieren (RØDECaster + Blackmagic noch verkabelt!)
- [ ] Issue dokumentieren, beim nächsten Mal beheben

**Erfolgreich = stabil 30+ Min auf beiden Streams, sauberer Audio, keine Drops.**

---

## 10. Fallback-Plan (falls am Sonntag was crasht)

**Goldene Regel: Altes Setup bleibt mindestens 4 Wochen physisch komplett erhalten!**

### Während der ersten 4 Sonntage
- RØDECaster Video bleibt eingestöpselt aber **inaktiv**
- Blackmagic Encoder bleibt eingestöpselt aber **aus**
- HDMI-Kabel von PTZs zum RØDECaster bleiben dran
- Falls neuer Stream crasht: alten Encoder einschalten, alte Verkabelung greift wieder

### Schnell-Switch (geübt in <2 Minuten)
1. Mac Mini OBS stoppen
2. Blackmagic Encoder einschalten
3. RØDECaster aktivieren
4. Alte X32-Routing Snapshot (falls vorhanden) laden
5. Streams in alten Geräten starten

### Erst nach 4 stabilen Sonntagen
- Doppel-Verkabelung abbauen
- RØDECaster + Blackmagic ausbauen, einlagern oder verkaufen

---

## 11. Aufbau-Zeit Vorher / Nachher

### Vorher (geschätzt)
| Schritt | Zeit |
|---|---|
| Hardware verkabeln (RØDECaster, Encoder, HDMI-Kabel) | 10 min |
| X32 + SD8 hochfahren, Übersetzer-Funkstrecke prüfen | 5 min |
| Mac OBS starten, Quellen prüfen | 5 min |
| Blackmagic Encoder konfigurieren, RU-Stream starten | 8 min |
| OBS DE-Stream starten | 3 min |
| Pegel + Bild final checken | 5 min |
| **Gesamt** | **~36 min** |

### Nachher (Schätzung nach Eingewöhnung)
| Schritt | Zeit |
|---|---|
| Mac Mini hochfahren / aus Standby (OBS startet automatisch) | 1 min |
| X32 hochfahren, Snapshot lädt automatisch | 2 min |
| Stream Deck → "Probe Bild + Ton" Knopf | 2 min |
| Pegel kurz prüfen | 2 min |
| Stream Deck → "STREAM START" | 1 min |
| **Gesamt** | **~8 min** |

**Ersparnis: ~28 Minuten pro Sonntag, ~24h pro Jahr.**

---

## 12. Sprint 2 — Custom Tertius Stream Control App (Vision)

**Wann?** Erst wenn das aktuelle Setup 6+ Wochen stabil läuft.

**Was?** iPad-App, die `obs-websocket` nutzt und das Stream Deck-Konzept auf einen großen Touchscreen bringt — visueller, mehr Live-Daten, mehr Sicherheit.

**Features-Vision:**
- Großer **STREAM START** Knopf, leuchtet rot wenn live
- **Live-Vorschau** beider Streams als Thumbnail
- **Pegel-Bargraphs** für DE + RU Audio in Echtzeit
- **Health-Dashboard:** "X32 verbunden ✓ / Front-Kamera ✓ / Seite-Kamera ✓ / Internet ✓"
- **Pre-Stream Checkliste** automatisch durchlaufen, Aushilfe muss nur abnicken
- **PTZ-Joystick** für Kamera-Schwenks zwischen Presets
- **Live-Untertitel-Vorschau** (siehe Sprint 3)

**Aufwand:** ~45h in Flutter, kann in 3 Wochenenden gebaut werden.

**Voraussetzung:** Sprint 1 (diese Doku) komplett umgesetzt + 4 Wochen stabil.

---

## 13. Sprint 3 — Live-Transcription auf Mac Mini lokal

**Wann?** Parallel oder nach Sprint 2.

**Was?** **whisper.cpp** läuft auf dem Mac Mini M1 mit Metal-Beschleunigung. Nimmt den Audio-Mix direkt aus OBS (oder X32-USB Track 1) ab, transkribiert in Echtzeit, übersetzt via DeepL, schickt an Tertius-Backend.

**Vorteile gegenüber Hetzner-VPS-Variante:**
- Audio verlässt **nie** den Saal → 100% DSGVO-konform
- Kein VPS nötig, keine zusätzlichen Kosten
- M1 Neural Engine ist schnell genug für large-v3 Modell in Realtime
- Bei Internet-Ausfall: Whisper läuft trotzdem, Texte werden gepuffert

**Architektur:**
```
X32 USB Track 1 (DE)
       │
       ▼
┌──────────────┐
│  Mac Mini    │
│  ┌────────┐  │
│  │whisper │──┼──> DE Text
│  │.cpp    │  │       │
│  └────────┘  │       ▼
│              │   ┌──────┐
│              │   │DeepL │──> RU Text
│              │   └──────┘
│              │       │
│              │       ▼
│              │   HTTP POST → Tertius Backend
└──────────────┘            (Live-Untertitel im Tertius-Player)
```

**Aufwand:** ~12h. Skript-basiert, lokal getestet bevor live.

---

## 13b. Sprint 4 — Guide-Tour Live-Übersetzung (mobile)

**Wann?** Sobald Sprint 3 (lokales Whisper) läuft — die Pipeline ist dann schon da.

**Was?** Eine **mobile Variante der Live-Transkription** für Führungen über das Mission-Gelände (oder andere Vor-Ort-Veranstaltungen). Der Guide spricht ins Handy/Headset, alle Besucher hören die Übersetzung in ihrer Sprache live auf ihrem eigenen Smartphone.

**Warum das ein Game-Changer ist (skalierbar &amp; null-Hardware):** Heute hat praktisch jeder Besucher ein Smartphone und Kopfhörer dabei. Wir brauchen keine Funkempfänger, keine Headsets zum Verleihen, keine Pfand-Listen. Eine Tour mit 5 Personen funktioniert genauso wie eine mit 200. Skaliert von einer Familienführung bis zur Großveranstaltung, ohne dass irgendwer extra Gerät anfassen muss. Tertius wird damit von „Streaming-App" zu **„Echtzeit-Übersetzungs-Plattform für Gemeinde-Events"**.

**Wie es konkret laufen soll:**
- Guide öffnet die Tertius-App, startet eine **„Tour"** und wählt die Quellsprache
- Die App generiert einen **kurzen Code** (z.B. „TOUR-7421") oder einen QR-Code
- Besucher scannen den Code → landen direkt im Live-Transcription-Viewer, wählen ihre Sprache (DE / EN / RU / RO / ZU)
- Audio vom Guide-Handy → Whisper (lokal auf Mac Mini oder Cloud Run als Fallback) → DeepL → Push an alle verbundenen Viewer-Geräte via Supabase Realtime
- Latenz-Ziel: **unter 4 Sekunden** vom Wort bis zum Untertitel

**Was wir dafür bauen müssen:**
- „Tour starten"-Screen für den Guide (großer Mikro-Knopf, Live-Pegel)
- Code/QR-Generator + Beitritts-Flow für Besucher
- Robuste WebRTC- oder Direct-Upload-Pipeline für Mobilfunk-Bedingungen (3G/4G im Außenbereich)
- Glossar für ortsspezifische Begriffe (Eigennamen, Personen, Gebäude — DeepL Glossary)
- Offline-Buffer falls Empfang abbricht

**Hardware-Empfehlung Guide:**
- Beliebiges modernes Smartphone reicht — empfohlen: kabelgebundenes Lavalier-Mikrofon (~30 €) für saubere Aufnahme bei Wind

**Aufwand:** ~25 h (Hauptarbeit ist die mobile Audio-Pipeline + Beitritts-Flow). Voraussetzung: Sprint 1 + 3 fertig, Glossar-Logik aus dem Pitlane-Construction-Übersetzer kann teilweise wiederverwendet werden.

---

## 14. Offene Punkte (vor Migration zu klären)

- [ ] **YouTube Stream-Keys** für DE und RU griffbereit haben (in 1Password o.ä.)
- [ ] **PTZ IP-Adressen** dokumentieren (falls nicht schon bekannt)
- [ ] **PTZ RTSP-URL Format** vor Ort testen (mit `ffplay` oder VLC)
- [ ] **X32 Edit App** auf Mac Mini installieren falls nicht da
- [ ] **OBS Multi-RTMP Plugin** auf Mac Mini installieren
- [ ] **Stream Deck OBS Plugin** im Stream Deck App-Marketplace installieren
- [ ] **PTZ.OBS Plugin** (optional) installieren
- [ ] **Termin für Probe-Stream** festlegen (Samstag vor Live-Sonntag)
- [ ] **Termin für Live-Test** festlegen (mit Backup-Verkabelung!)

---

## 15. Risiken und Gegenmaßnahmen

| Risiko | Wahrscheinlichkeit | Gegenmaßnahme |
|---|---|---|
| RTSP-Stream der PTZ ist instabil | mittel | Reconnect-Delay in OBS, im Notfall HDMI-Backup über USB-Capture-Karte (~50 EUR) |
| OBS crasht während Live | niedrig | Mac Mini Auto-Restart Script + OBS auto-resume on launch |
| Internet-Ausfall mitten im Stream | niedrig | OBS hat Auto-Reconnect, Hardware-Encoder buffern kurz |
| Stream-Key wird ungültig | niedrig | Im Stream Deck "Reset Keys" Knopf (lädt Keys neu aus Datei) |
| Aushilfe drückt falschen Knopf | hoch | Kritische Knöpfe (STREAM STOP) auf zweite Druckbestätigung legen |
| X32 USB-Verbindung trennt sich | niedrig | Hochwertiges USB-Kabel, gegen Kabelzug sichern |
| Mac Mini friert ein | sehr niedrig | M1 ist extrem stabil, Watchdog-Skript optional |

---

## 16. Geschätzter Gesamtaufwand

| Phase | Aufwand |
|---|---|
| **Vorbereitung** (Plugins installieren, X32 Edit Snapshot bauen) | 2h |
| **Probe-Stream** (privat, einmal komplett durchspielen) | 2h |
| **Migration durchführen** (samstags vor erstem Live-Test) | 2h |
| **Erster Live-Test** (mit Backup-Verkabelung) | 1h Begleitung |
| **Stream Deck Layout finalisieren** | 1h |
| **Doku für Aushilfen schreiben** (1-Pager) | 1h |
| **Gesamt Sprint 1** | **~9h** |

Verteilbar auf 2-3 Wochenenden in Etappen.

---

## 17. Nächste Schritte

1. **Diese Doku in Ruhe lesen**, Fragen sammeln
2. **Termine setzen** für Vorbereitung + Probe-Stream + erstes Live
3. **Plugins downloaden** (Multi-RTMP, Stream Deck OBS Plugin) — kannst du schon vorab machen
4. **PTZ IPs + RTSP-URLs** beim nächsten Saal-Aufenthalt notieren
5. **Beim ersten echten Migration-Schritt** zusammen durchgehen — ich bin live dabei, wenn du willst

---

**Fragen oder Ergänzungen?** → Diese Doku lebt, einfach unten ergänzen.

**Letzte Überarbeitung:** 2026-04-07 — Erstversion, alle Hardware-Daten erfasst (X32 Rack, SMTAV PTZ 30x, Mac Mini M1 16GB, Stream Deck +, kein YouTube Multi-Audio → Multi-RTMP).
