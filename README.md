# BlessingMaster

Ein PallyPower-artiges Addon für **World of Warcraft: The Burning Crusade Classic**.
BlessingMaster übernimmt die komplette Blessing-Logistik im Raid: Es errechnet
automatisch, welcher Paladin wem welchen Segen (Greater oder einzeln) gibt,
hält alle Paladin-Addons live synchron und warnt visuell, wenn jemand seinen
Segen nicht (mehr) hat.

## Installation

1. Repo-Inhalt nach `World of Warcraft/_classic_/Interface/AddOns/BlessingMaster/`
   kopieren, sodass `BlessingMaster.toc` direkt in diesem Ordner liegt.
2. Falls das Addon im Spiel als "veraltet" markiert wird: `## Interface` in
   `BlessingMaster.toc` an die aktuelle Client-Version anpassen
   (Format `MAJOR MINOR PATCH` ohne Punkte, z. B. Patch 2.5.4 → `20504`).
3. `/reload` bzw. Client neu starten, Addon im Char-Auswahlbildschirm aktivieren.

## Bedienung

- `/bm` oder `/blessingmaster` – Hauptfenster ein-/ausblenden
- `/bm compact` – Kompaktmodus umschalten
- `/bm lock` – Fenster sperren/entsperren (auch per Button im Fenster)
- `/bm reset` – Fensterposition zurücksetzen
- `/bm recalc` – Zuteilung manuell neu berechnen
- Minimap-Button: Linksklick öffnet/schließt das Fenster, Rechtsklick sperrt
  es, Ziehen verschiebt den Button.

## Funktionsübersicht

- **Smart Assignment**: Pro Raidgruppe wird automatisch die sinnvollste
  Greater Blessing bestimmt (Mehrheitsvotum nach Klasse/Rolle der Mitglieder)
  und auf verfügbare Paladine verteilt (Round-Robin, falls weniger Paladine
  als Gruppen vorhanden sind). Mitglieder, deren Wunsch-Segen vom
  Gruppen-Segen abweicht, bekommen automatisch einen gezielten Einzel-Segen
  (Tier-2-Patch) vom am wenigsten ausgelasteten Paladin.
- **Greater vs. Einzel-Segen**: Beide Varianten werden getrennt geführt
  (`greaterSpellId` / `singleSpellId` je Segen in `Constants.lua`) und im UI
  unterschiedlich markiert (goldener vs. grauer Rahmen, "G-"-Präfix).
- **Lokalisierungsunabhängig**: Segen werden intern über numerische
  Spell-IDs identifiziert statt über englische Namen. Name und Icon werden
  zur Laufzeit per `GetSpellInfo(id)` in der Sprache des jeweiligen Clients
  aufgelöst (`BM:GetSpellName`/`BM:GetSpellIcon`) - das Addon funktioniert
  dadurch auch auf deutschen, französischen etc. Clients. Beim Login prüft
  `BM:ValidateSpellIds()`, ob alle konfigurierten IDs auf dem aktuellen
  Client auflösbar sind, und warnt im Chat, falls nicht.
- **Live-Sync zwischen Paladinen**: Über einen Addon-Kommunikationskanal
  (`CHAT_MSG_ADDON`, Prefix `BlessingMstr`) wählen alle Paladin-Clients
  deterministisch denselben "Koordinator" (Raidleiter > Assist > alphabetisch
  erster bekannter Paladin). Nur der Koordinator berechnet die Zuteilung und
  sendet sie an alle anderen; Beitritte/Reconnects lösen automatisch eine
  Neuberechnung + erneuten Broadcast aus (`GROUP_ROSTER_UPDATE`).
- **Fehlende-Buff-Warnung**: `BuffTracker.lua` scannt alle zugeteilten
  Spieler alle 2 Sekunden per `UnitBuff`; fehlt/weicht der Segen ab, wird der
  Icon-Rahmen in der Raid-Übersicht rot/orange.
- **Ausschluss pro Spieler**: Rechtsklick auf eine Zeile → "Von
  Auto-Zuteilung ausschließen" (z. B. AFK-Spieler oder Selbstbuffer).
- **Presets pro Encounter**: Beliebig viele Profile mit eigenen
  Klassen-/Rollen-Prioritäten, Ausschlüssen und Zwangs-Zuteilungen; über das
  Dropdown im Fenster wechselbar.
- **Export/Import**: Presets lassen sich als Copy-&-Paste-String
  (`BM1:...`, Base64-kodiert) teilen und importieren – ähnlich wie
  WeakAuras-Strings.
- **Kollisions-Check**: Wird trotz Sync versehentlich derselben Gruppe von
  zwei verschiedenen Paladinen eine unterschiedliche Greater Blessing
  zugewiesen, wird das als Kollision erfasst (`plan.collisions`).
- **"Alle casten"-Leiste**: Jede Zuteilung bekommt einen eigenen sicheren
  Button (klickbar jederzeit); der "Alle casten"-Button klickt sie **außerhalb
  des Kampfes** automatisch nacheinander durch (~0,55 s Abstand wegen GCD).
  Blizzard erlaubt keine mehreren Zauber pro Tastendruck in einem Makro –
  im Kampf bleibt daher nur das manuelle Anklicken der einzelnen Icons.
- **Minimap-Button + verschiebbares/skalierbares Fenster**: Position, Skalierung
  und Sperrzustand werden in den SavedVariables gespeichert.
- **Kompaktmodus**: Reduziert das Fenster auf Titel + eigene Zuteilungsicons.
- **Raid-Warnung bei Neuzuteilung**: Ändert sich die berechnete Zuteilung
  spürbar, schickt der Koordinator automatisch eine Nachricht in den
  Raidchat/Raid-Warnung ("Zuteilung aktualisiert - bitte Blessings neu
  setzen!").

## Bekannte Einschränkungen

- Die in `Constants.lua` hinterlegten Spell-IDs wurden per Web-Recherche
  zusammengestellt (Wowhead-Direktzugriff war in der Entwicklungsumgebung
  blockiert) und stammen von den unter `wowhead.com/tbc/...` als
  "TBC Classic" gekennzeichneten Einträgen. Da Rang/ID-Zuordnungen sich
  zwischen dem originalen TBC (2007) und dem Classic-Relaunch teils
  unterscheiden, unbedingt nach dem ersten Login die Chat-Ausgabe prüfen:
  Meldet `BM:ValidateSpellIds()` eine nicht auflösbare ID, in `Constants.lua`
  die betroffene `*SpellId`-Zahl anhand der eigenen Zauberbuch-Tooltips oder
  z. B. `/dump GetSpellInfo(19838)` im Spiel korrigieren.
- Die Sync-Logik geht davon aus, dass alle beteiligten Paladine
  BlessingMaster installiert haben; Paladine ohne Addon werden nicht als
  Caster eingeplant, tauchen aber weiterhin als normales Raidmitglied
  (Empfänger) auf.
- "Alle casten in einem Klick" ist während des Kampfes aus Blizzard-seitigen
  Gründen (ein Zauber pro Tastendruck) nicht möglich – vor dem Pull
  funktioniert es wie vorgesehen vollautomatisch.
- Getestet wurde die Zuteilungslogik mit einem Lua-Mock-Harness außerhalb des
  Spiels (`Assignment.lua`/`Profiles.lua`); ein Live-Test im Spielclient wird
  empfohlen, bevor es im Raid produktiv eingesetzt wird.

## Dateien

| Datei | Zweck |
|---|---|
| `Core.lua` | Bootstrap, SavedVariables, Event-Bus, Slash-Commands |
| `Constants.lua` | Segen-/Spell-Daten, Klassen-Rollen-Defaults |
| `Roster.lua` | Raid-/Gruppen-Scan, Paladin-Liste |
| `Profiles.lua` | Presets, Export/Import |
| `Assignment.lua` | Smart-Assignment-Algorithmus, Kollisions-Check |
| `Comm.lua` | Addon-Sync, Koordinator-Wahl, Raid-Warnung |
| `BuffTracker.lua` | Fehlende-Buff-Erkennung |
| `CastBar.lua` | Sichere Cast-Buttons, "Alle casten" |
| `UI.lua` | Hauptfenster, Kompaktmodus, Kontextmenü |
| `Minimap.lua` | Minimap-Button |
