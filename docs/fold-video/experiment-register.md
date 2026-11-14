# Proefregister Fold / DroidVM

Bijgewerkt: 14 november 2026. Dit is het centrale beslisregister voor de Fold-proeven op deze voortgangsbranch. De hoofdchat werkt dit na elke betekenisvolle proef bij. Het register begint met de hieronder gecontroleerde resultaten; het is geen volledige reconstructie van alle eerdere kandidaten.

## Werkafspraak: eerst merkbare gebruikswinst

De gebruiker heeft op 14 november 2026 gevraagd om sneller en minder perfectionistisch te werken, herhaling te voorkomen en de uitkomsten op GitHub te bewaren.

- Kies per stap één concrete gebruikstaak en één hypothese. Noteer vooraf wat zichtbaar of meetbaar beter moet worden en wanneer we beslissen.
- Doe eerst de kleinste proef die die beslissing kan dragen. Een beperkte maar bruikbare verbetering mag worden bewaard met bekende beperkingen; video, 3D en fysiek vouwen hoeven niet iedere tussenstap samen te halen.
- Uitgebreide stressproeven, optimalisaties en bredere architectuurveranderingen volgen alleen als het huidige resultaat of een concrete fout ze nodig maakt. Voeg voor het register geen nieuwe controleharnas of uitgebreide reviewronde toe.
- Na maximaal twee gerichte mislukte pogingen op dezelfde hypothese: kort beslissen tussen doorgaan met nieuwe aanwijzingen, parkeren of een andere richting. Noodzakelijke bouwtijd telt niet als een nieuwe proef.
- Herhaal een bestaande combinatie alleen met een vermelde reden: gewijzigde code/configuratie, ongeldige eerdere meting, of een gerichte controle op herhaalbaarheid.
- Behoud herstelbaarheid en bescherming van gebruikersgegevens. Een crash, zwart beeld of vastgelopen backend blijft een concrete beperking; een beperkte proef is geen algemene vrijgave.
- Lees dit register vóór een nieuwe proef. Vul na een betekenisvolle uitkomst dezelfde rij aan of voeg één rij toe, commit en push vóór de volgende variant. Bij een noodzakelijke herstelactie eerst herstellen en daarna vastleggen.
- Rapporteer kort: wat merkt de gebruiker, wat blijft beperkt, welke beslissing volgt. Een geslaagde API-controle of build is apart van bruikbaarheid.

## Resultaten en beslissingen

| Proef / versie | Hypothese en scenario | Waargenomen resultaat | Beslissing / herhaalvoorwaarde | Bewijs |
| --- | --- | --- | --- | --- |
| Videostack met C4; AV1 1080p60 | Hardwaredecode verlaagt CPU ten opzichte van softwaredecode op dezelfde ontwikkelstack; één sequentieel paar, 20 s CPU per stand | Edge 6,65% versus 22,44%; hele Windows-gast 11,02% versus 28,53%; circa 59,1 fps in beide standen. Merkbare CPU-winst aannemelijk; beeldglitches blijven. Het afzonderlijke CPU-effect van C4 is niet geïsoleerd | CPU-resultaat bewaren als beperkte winst. Niet opnieuw benchmarken zonder specifieke aanleiding; beeldcorrectheid blijft een afzonderlijk verbeterpunt | [Validatie](video-validation.md#cpu-comparison), [meetgegevens](cpu-decode-comparison.json) |
| C16 RuntimeON, R2-meting | Native GPU-uitvoering moet correcte, vloeiende 3D leveren; 30 s kubusscène op fysiek scherm | 369 presents / 30,039 s = 12,284 fps. Alle 15 kubussen in 374 opgenomen scèneframes; kleurcorruptie bijschrift blijft. API-proef slaagt, gebruiksdoel niet | Variant gesloten. Niet ongewijzigd herhalen. De fysieke controlemeting was ongeldig, dus geen causale OFF/ON-snelheidsclaim | Lokaal: `evidence/c16-final-controlled-phase-decision.json` |
| C17 profielproef, copy-0-r1 | Instrumentatie moet de oorzaak van de lage snelheid aanwijzen | Afgebroken tijdens opwarming: runtime-callback geweigerd. Geen geldige gemeten fase; dus geen fps- of beeldconclusie | Gesloten als mislukte diagnoseproef. Alleen herhalen na gerichte correctie of verbeterde foutdiagnose | Lokaal: `evidence/c17-diagnostic-failure-decision.json`, `evidence/current-work-state-c17.json` |
| C18 profielproef, copy-0-r1 | Verfijnde diagnose op dezelfde runtime-route | Profiel eindigt normaal; circa 12,505 fps en bijschriftcorruptie blijven. API-/procesgezondheid slaagt; nog geen merkbare snelheidswinst | Uitkomst bewaren; geen algemene succesclaim. Vervolg moet een concrete fout herstellen of een gebruikstaak aantoonbaar verbeteren | Lokaal: `evidence/c18-owned-bench-profile-r1-controller-result.json`, `evidence/current-work-state-c17.json` |
| C19 native `21EA…`, EC `6333…`, F91 | CB-setters en geschikte DWM-schermbuffers bundelen; lokaal scherm openen en resolutie 2448×1848→2448×1144 | Zwart beeld vóór benchmark; Windows bereikbaar en GPU Code0. Submit `0x80070057` bevat oud geopend bufferhandvat `40002b40`, terwijl hetzelfde hergebruikte object nieuw schermhandvat `40003140` kreeg. Geen benchmark gestart, dus geen fps-resultaat | Deze proef gesloten. Eén gerichte constructorcorrectie in C20; bundelingswinst blijft onbekend. Normale gastafsluiting lukte, backend bleef hangen; geautoriseerde telefoonherstart herstelde die toestand | Lokaal: `evidence/c19-black-native-pretrial-neptune.log`, SHA256 `37db89616e11331ae7544addd1a00c81c94c96a9e1231c4d6975f987628ffdbb`; `evidence/c19-native-fullscreen-after-settle.png` |
| C20 native `5789…`, EC `9CC9…`, F91; in behandeling | C19 + alleen `RuntimeOpenedAllocation = 0` bij CreateResource. Verwacht zichtbaar bureaublad na dezelfde scherm-/resolutiewissel; vervolgens korte echte 3D-taak | Productiebron-regressie: baseline en verwijderde-resetmutant kiezen fout oud handle; correctie kiest nieuw handle. Native/EC-builds geslaagd; nog geen toestel-/gebruiksresultaat | Nu exact het zwarte-beeldscenario één keer testen. Bij herstel meteen dezelfde kubusapp zichtbaar beoordelen, daarna video. Geen bredere stressronde vooraf | Lokaal: `artifacts/proposals/runtime-opened-allocation-reset-c20-r1/manifest.json` SHA `BE9AE2AF…99DF33`; `artifacts/c20-umd-build/session-20261114-opened-init-r1/final-local-verification.json` SHA `2a20630f…9112617` |

De lokale bewijsnamen verwijzen naar bestaande meetbestanden in de gedeelde werkmap, niet naar op GitHub aanwezige logs. De openbare CPU-samenvatting is direct gelinkt. Voeg bij nieuwe proeven kandidaat/build-identiteit, scenario en compact bewijs toe; publiceer geen wachtwoorden of apparaatidentificatie.

## Eerstvolgende beslissing

Bevestig of de gerichte bufferhergebruikcorrectie het zwarte beeld verhelpt. Bewaar een bruikbaar tussenresultaat met beperkingen; start geen brede nieuwe verbeterroute zonder de uitkomst van die proef.

## Exacte kandidaat-identiteiten

C19 native/alias SHA256: `21EA6DC5C01F627DE665F0D01F5EF89476647F84B56BDC1DE747BDD2D258C6B8`; EC: `6333DF83DDD99B8D61432CE15B72C081E43B3A1A847EFFA5085B082CB79ABC02`.

C20 native/alias SHA256: `57899B8A56CF4FD36E8F62DBEB6125E23365BEC7453B95F529ABBE438C09AD9A`; EC: `9CC91ED21D0FA367CCF070483A83949C9695504D26CAB4F939E3613A2E598C2D`. C20 verandert één regel in één bronbestand tegenover C19; 442 andere bronbestanden blijven gelijk. KMD en Android-hoststack blijven gelijk.
