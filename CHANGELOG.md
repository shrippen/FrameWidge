# Changelog

## [1.3] — 2026-10-18

### English

FrameWidge brings its own service, framewidged, instead of depending on framework-control, whose 0.5.5 had moved the fan settings out of reach. The widget talks to it over D-Bus, the Power tab switches the system power profile, and the popup can take the Kante look.

#### New
- Own service `framewidged` (Rust): fan curve and manual duty (also per fan), charge limit and charge rate, sensor history. It reads sensors and battery from the kernel and writes to the embedded controller through Framework's `framework_tool`.
- The widget talks to the service over the system bus; changing settings is checked by polkit (free for the person at the laptop, an admin password for anyone else).
- Power tab: the system power profile (Power Saver, Balanced, Performance) through power-profiles-daemon or tuned-ppd, the same setting as Plasma's battery applet.
- Fan curve presets live in the service and can switch on by themselves when the laptop is plugged in or unplugged, also with the widget closed.
- Style setting for the popup: System (default), Kante or Kante Light. The Kante styles draw the fan curve, the sensor chart with hover read-out and legend, the tray colour bands and the install commands with Kante's own elements.
- German translation of the widget.

#### Improved
- When the service stops or crashes, the fans go back to the firmware's own curve; so they do when a curve has no temperature to follow, until readings return.
- No tab scrolls at the default popup size: the popup is taller and each tab scrolls by its own height; the sensor choice and time range show without scrolling.
- Sensors carry the names of the current `framework_tool` (0.6.6), such as `cpu@4c` and `APU Fan`.
- Sensor line colours in the System style are spread evenly; CPU and Battery no longer share one colour.
- `uninstall.sh` offers to remove the service too.

#### Fixed
- Fan curve: switching the separate down rate off took no effect; the old rate stayed.
- The Fan page fits the popup: hysteresis, rate limits and poll interval stack one per row on narrow popups instead of clipping the curve editor.
- System curve editor: marker captions move left of the guide when a point's handle would cover them.

#### Note
- `install.sh` installs `framewidged` with its D-Bus policy and polkit action, and `framework_tool` if missing, and stops and disables framework-control. On its first start framewidged takes over `/etc/framework-control/config.json` (fan settings of the active profile, calibration of the first fan, battery, telemetry); presets saved with 1.2 and fan curves with the old sensor names are moved over once.
- Needs Plasma 6.1 or newer. The service port setting and the web UI link are gone.
- The separate AC and battery settings for governor, EPP, frequency limits, TDP and thermal limit are gone: they fought with the power profile daemon over the same files.
- Kante's line chart has no time axis yet; the hover read-out shows the time.

All changes: https://github.com/shrippen/FrameWidge/compare/1.2...1.3

### Deutsch

FrameWidge bringt seinen eigenen Dienst mit, framewidged, statt von framework-control abzuhängen, dessen Version 0.5.5 die Lüftereinstellungen unerreichbar gemacht hatte. Das Widget spricht über D-Bus mit ihm, der Energie-Tab schaltet das Energieprofil des Systems, und das Fenster kann das Kante-Aussehen annehmen.

#### Neu
- Eigener Dienst `framewidged` (Rust): Lüfterkurve und feste Drehzahl (auch je Lüfter), Ladegrenze und Laderate, Sensorverlauf. Er liest Sensoren und Akku aus dem Kernel und schreibt über Frameworks `framework_tool` in den Embedded Controller.
- Das Widget spricht über den Systembus mit dem Dienst; Änderungen prüft polkit (frei für die Person am Laptop, ein Admin-Passwort für alle anderen).
- Energie-Tab: das Energieprofil des Systems (Energiesparen, Ausgewogen, Leistung) über power-profiles-daemon oder tuned-ppd, dieselbe Einstellung wie im Akku-Applet von Plasma.
- Lüfterkurven-Presets liegen im Dienst und können sich beim Ein- oder Ausstecken des Netzteils selbst einschalten, auch bei geschlossenem Widget.
- Stil-Einstellung für das Fenster: System (Standard), Kante oder Kante Light. Die Kante-Stile zeichnen Lüfterkurve, Sensordiagramm mit Anzeige beim Überfahren und Legende, die Farbbänder des Tray-Symbols und die Installationsbefehle mit Kantes eigenen Elementen.
- Deutsche Übersetzung des Widgets.

#### Verbessert
- Stoppt oder stürzt der Dienst ab, kehren die Lüfter zur eigenen Kurve der Firmware zurück; ebenso, wenn eine Kurve keine Temperatur zum Folgen hat, bis wieder Messwerte kommen.
- Bei der Standardgröße scrollt kein Tab: Das Fenster ist höher, und jeder Tab scrollt nach seiner eigenen Höhe; Sensorwahl und Zeitraum stehen ohne Scrollen da.
- Sensoren tragen die Namen des aktuellen `framework_tool` (0.6.6), etwa `cpu@4c` und `APU Fan`.
- Die Linienfarben der Sensoren im System-Stil sind gleichmäßig verteilt; CPU und Akku teilen sich keine Farbe mehr.
- `uninstall.sh` bietet an, auch den Dienst zu entfernen.

#### Behoben
- Lüfterkurve: Das Ausschalten der eigenen Abwärtsrate wirkte nicht; die alte Rate blieb.
- Die Lüfterseite passt ins Fenster: Hysterese, Ratengrenzen und Abfrageintervall stehen in schmalen Fenstern je in einer Zeile, statt den Kurveneditor abzuschneiden.
- Kurveneditor im System-Stil: Die Beschriftungen der Markierungen rücken links neben die Hilfslinie, wenn der Griff eines Punkts sie verdecken würde.

#### Hinweis
- `install.sh` installiert `framewidged` mit seiner D-Bus-Richtlinie und polkit-Aktion und, falls es fehlt, `framework_tool`, und stoppt und deaktiviert framework-control. Beim ersten Start übernimmt framewidged `/etc/framework-control/config.json` (Lüftereinstellungen des aktiven Profils, Kalibrierung des ersten Lüfters, Akku, Telemetrie); mit 1.2 gespeicherte Presets und Lüfterkurven mit den alten Sensornamen werden einmal übernommen.
- Braucht Plasma 6.1 oder neuer. Die Einstellung für den Dienst-Port und der Link zur Web-Oberfläche entfallen.
- Die getrennten Netz- und Akku-Einstellungen für Governor, EPP, Frequenzgrenzen, TDP und Temperaturgrenze entfallen: Sie stritten mit dem Energieprofil-Dienst um dieselben Dateien.
- Das Liniendiagramm von Kante hat noch keine Zeitachse; die Anzeige beim Überfahren zeigt die Uhrzeit.

## [1.2] — 2026-09-20

### English

A new logo.

#### Improved
- The tray uses a monochrome logo that follows the panel's text colour; the app icon uses the variant with the colour accent.

All changes: https://github.com/shrippen/FrameWidge/compare/1.1...1.2

### Deutsch

Ein neues Logo.

#### Verbessert
- Das Tray-Symbol nutzt ein einfarbiges Logo, das der Textfarbe des Panels folgt; das App-Symbol die Variante mit Farbakzent.

## [1.1] — 2026-09-20

### English

The tray shows its values from the start, and FrameWidge is in the KDE Store.

#### Fixed
- The tray overlay (temperature, RPM or charge) loads its data at startup instead of staying empty until the popup is opened for the first time.

#### Note
- The widget is available in the KDE Store; its description points to the install script, which also sets up the backend.

All changes: https://github.com/shrippen/FrameWidge/compare/1.0...1.1

### Deutsch

Das Tray-Symbol zeigt seine Werte von Anfang an, und FrameWidge ist im KDE Store.

#### Behoben
- Die Anzeige auf dem Tray-Symbol (Temperatur, Drehzahl oder Ladestand) lädt ihre Daten beim Start, statt leer zu bleiben, bis das Fenster zum ersten Mal geöffnet wird.

#### Hinweis
- Das Widget gibt es im KDE Store; seine Beschreibung verweist auf das Installationsskript, das auch das Backend einrichtet.

## [1.0] — 2026-09-19

### English

The first release of FrameWidge, a KDE Plasma 6 tray widget for Framework laptops on top of the framework-control backend.

#### New
- Fan control: auto, manual duty, a drag-and-drop curve editor, hysteresis, rate limits, per-fan overrides (Framework 16) and a calibration wizard.
- Sensors: live temperature graphs with a sensor choice and an adjustable time window.
- Power: AC and battery profiles, EPP, governor, frequency limits, TDP and thermal controls, as far as the hardware offers them.
- Battery: charge and discharge power, health, cycles, charge limit (25–100 %) and a charge rate limit.
- Tray: temperature, RPM or charge on the icon, and a tooltip with live values.
- A setup guide when the backend is missing or stopped.

### Deutsch

Die erste Version von FrameWidge, einem Tray-Widget für KDE Plasma 6 auf Framework-Laptops, auf dem Backend framework-control.

#### Neu
- Lüftersteuerung: automatisch, feste Drehzahl, ein Kurveneditor zum Ziehen, Hysterese, Ratengrenzen, Einstellungen je Lüfter (Framework 16) und ein Kalibrierungsassistent.
- Sensoren: Temperaturverläufe in Echtzeit mit Sensorwahl und einstellbarem Zeitfenster.
- Energie: Profile für Netz und Akku, EPP, Governor, Frequenzgrenzen, TDP und Temperaturgrenzen, soweit die Hardware sie bietet.
- Akku: Lade- und Entladeleistung, Zustand, Zyklen, Ladegrenze (25–100 %) und eine Begrenzung der Laderate.
- Tray: Temperatur, Drehzahl oder Ladestand auf dem Symbol und ein Tooltip mit aktuellen Werten.
- Eine Einrichtungshilfe, wenn das Backend fehlt oder gestoppt ist.
