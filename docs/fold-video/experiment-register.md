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
| Correctie na C19, in behandeling | Hoofdchat meldt een oud bufferhandvat bij hergebruik; een gerichte initialisatiecorrectie moet het scenario met zwart beeld herstellen | Diagnose en bouw gemeld; nog geen door deze registratie bevestigde geslaagde gebruiksproef | Eerst hetzelfde zwarte-beeldscenario één keer gericht controleren. Bij herstel een korte echte gebruikstaak proberen; uitkomst in deze rij vastleggen vóór verbreding | Recente voortgangsmededeling hoofdchat; nog geen gepubliceerde runtimevalidatie |

De lokale bewijsnamen verwijzen naar bestaande meetbestanden in de gedeelde werkmap, niet naar op GitHub aanwezige logs. De openbare CPU-samenvatting is direct gelinkt. Voeg bij nieuwe proeven kandidaat/build-identiteit, scenario en compact bewijs toe; publiceer geen wachtwoorden of apparaatidentificatie.

## Eerstvolgende beslissing

Bevestig of de gerichte bufferhergebruikcorrectie het zwarte beeld verhelpt. Bewaar een bruikbaar tussenresultaat met beperkingen; start geen brede nieuwe verbeterroute zonder de uitkomst van die proef.
