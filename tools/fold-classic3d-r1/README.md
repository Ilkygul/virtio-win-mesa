# DroidVM 3D-demo met klassieke titelbalk

Een vaste Direct3D 11-demo voor Windows ARM64 in DroidVM: 15 kubussen, een privé renderdoel en één volledige framekopie naar de schermbuffer. De launcher past alleen de titelbalk van zijn eigen demovenster aan. De meting duurt 30 seconden na 1 seconde opwarming, met een clientoppervlak van 960×640 en vsync aan.

**Op de productie-VM getest op 14 november 2026.** De geïnstalleerde snelkoppeling startte deze pakketversie: 1810 presents in 30,013541 s (60,306 API-fps), natuurlijke exit0, lege stderr en GPU-foutcode0. Alle 1832 actieve opnameframes bevatten 15 kubussen; nul felmagenta captionpixels en leesbare klassieke titeltekst. Alleen de eigen vensterpolicy veranderde enabled1→0, met client960×640 behouden. Dit is een beperkte productie-demo, geen algemene vrijgave van Windows-graphics.

Download het volledige ZIP-pakket via de [GitHub-release](https://github.com/Ilkygul/virtio-win-mesa/releases/tag/fold-classic3d-20261114-r1). De bronmap in Git bevat de scripts en broncode; de geteste EXE zit in het releasebestand.

## Vereisten

- Windows ARM64, een werkende hardwarematige D3D11-route en Windows PowerShell 5.1.
- De bestaande geteste driverbaseline: KMD SHA256 `1CA24128E436F6A0EEDA4896DE01B3FE3B5EC0BFED51B4CDE3076AB501DE51E4`; native UMD SHA256 `3EEF8F3E4EC844E05A09E7F5BB5B1B5661AF85E1DCC5CA8D5EE5177FACB31FBD` (C8-baseline). Dit pakket levert of installeert geen drivers.
- De bestaande lege bestanden `C:\Users\Public\triton-presentwritesync` en `C:\Users\Public\triton-dwmwritesync` moeten beide aanwezig blijven. De launcher controleert ze en maakt of wijzigt ze niet.
- Pak de volledige map uit op een blijvende, beschrijfbare locatie. Gebruik het lokale interactieve Windows-bureaublad; een RDP-sessie is geen bewijs van het fysieke DroidVM-scherm.

## Installeren en starten

Open Windows PowerShell als de beoogde bureaubladgebruiker in de uitgepakte pakketmap:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-desktop-shortcut.ps1
```

De installer controleert de vaste EXE-/supervisor-/launcherhashes, parseert de scripts, maakt zo nodig de map `runs` en maakt de snelkoppeling **DroidVM 3D-demo - klassieke titelbalk**. Hij start de demo niet en overschrijft geen bestaande snelkoppeling. Laat de pakketmap daarna op dezelfde plaats staan.

Dubbelklik op de snelkoppeling. Elke start krijgt een eigen map onder `runs` met `plan.json`, `supervisor.json`, `benchmark.json` en `nonclient-result.json`. Wacht op het natuurlijke einde. De vensterontdekking wacht maximaal30seconden, zodat de in de eerste productieproef waargenomen koude start van14,3seconden binnen de begrensde observatie past. De launcher controleert procesidentiteit en HWND-eigendom voordat hij de nonclient-policy toepast, controleert dat de client 960×640 blijft en herstelt de oorspronkelijke enabled-state zolang het eigen venster nog bestaat. Bij venstervernietiging vervalt de instelling met dat venster.

De launcher bevat geen globale themawijziging, proceskill, driverinstallatie of automatische reboot. Een timeout geldt als onbevestigd einde; het script doet dan geen geforceerd herstel. Start geen tweede exemplaar om een vastgelopen eerste run te verbergen.

Verwijderen: verwijder alleen de genoemde bureaubladsnelkoppeling. Bewaar desgewenst de `runs`-map als bewijs voordat de pakketmap wordt verwijderd.

## Wat eerder is waargenomen

De eerdere daadwerkelijke snelkoppelingstest op een aparte test-VM gebruikte dezelfde EXE en supervisor: 1807 presents in 30,010548 s, circa **60,212 API-fps**, natuurlijke exit0 en lege stderr. Alle **1844 actieve opgenomen scèneframes** bevatten de 15 kubussen; in de gecontroleerde caption-ROI werden geen felmagenta pixels gevonden en de klassieke titeltekst was leesbaar. De policy veranderde enabled 1→0 zonder wijziging van het clientoppervlak.

Dat is een beperkte appgerichte workaround. API-fps bewijst geen fysieke 60-Hz-weergave. Andere apps, rechtstreeks tekenen in gedeelde schermbuffers en de algemene DWM-/WinUI-corruptie zijn hiermee niet hersteld. Videodecode- en vouwresultaten zijn afzonderlijke eerdere proeven, niet metingen van dit pakket.

De C4-videoviewbron en historische CPU-resultaten in `docs/fold-video` horen bij een afzonderlijke bronwijziging/ontwikkelmeting. Zij zijn geen bewijs dat dit pakket een nieuwe C4-driver bouwt, installeert of algemeen valideert.

## Bron en opnieuw bouwen

De meegeleverde bron is `native-present-copy-probe.cpp`, SHA256 `667F84D52F32EB6B265F03ABB4A45227959DC664814172F595DDA233F733FDEE`. De daadwerkelijk gebruikte EXE is native ARM64 (AA64), 1813504 bytes, SHA256 `6BEF5EAC5D4BB30E6D49DB6EE1612802EF6CE71C956D6132A639D2CC9BFA1C59`. De supervisor heeft SHA256 `DEFA9B78D92538772E829C6A2F8656F96473A23A06408E55121E506E036F07D4`.

Voor een eigen build zijn Visual Studio C++ ARM64-buildtools en een Windows SDK nodig op een x64 Windows-buildhost. Het meegeleverde `build-demo.ps1` gebruikt dezelfde daadwerkelijke MSVC ARM64-commandoregel als de oorspronkelijke build en schrijft uitsluitend naar een nieuwe uitvoermap:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-demo.ps1 -OutputDirectory .\build-arm64-1
```

De oorspronkelijke build rapporteerde MSVC/linker 14.44 en geen compilerwaarschuwingen. Een andere compiler/SDK, tijdstempel of PDB-pad kan andere binaryhashes opleveren. Het script bewaart bronhash, compilerpad/-versie, logs, PE-rapporten en hashes. Het bouwt geen driver en voert de demo niet uit. De launcher blijft aan de geteste release-EXE gebonden; vervang die niet stilzwijgend door een eigen build.

## Productiecontrole en bekende beperkingen

De eerste productieproef paste de policy niet toe doordat het proces pas na de oorspronkelijke12s-ontdekdeadline verscheen. Die run is afgewezen. De enige functionele launchercorrectie verlengt deze deadline tot30s; eigendoms-, hash-, client- en herstelcontroles blijven gelijk. Een volgende muisdubbelklik die geen workload startte is geen meetproef; de geldige vervolgproef gebruikte interactieve ShellExecute van exact dezelfde geïnstalleerde snelkoppeling.

De volledige geldige opname bevat1872bronframes/50,444678s, waarvan1832actieveframes/31,061s;22opstartframes en18afsluitende bureaubladframes zijn apart bewaard. De opstartfase kan kort een desktopgevuld venster tonen. Geen ontbrekende kubusslots of andere zichtbare sterke captionkleurcorruptie in de actieve scène. Geometriecontrole perframe en tekstinspectie in tijdlijn/first/last/worst-samples zijn geen controle van iedere fysieke schermverversing of ieder pixel.

Korte productie-videocontrole: AV11080p60 via D3D11VideoDecoder/platformtrue en actieve QTIAV1-decoder;58,981browserfps,30drops/1797frames,media29,966svooruit/29,959smeting,alle samples ongepauzeerd. WindowsCPU12,285% enEdge4,993% tijdens20,028s binnen de meting, stabiele Edgeprocesgroep. De eerste cookiedialoogmeting was ongeldig en is vervangen na expliciet afwijzen van cookies. Dit bewijst hardwaredecode en behouden bruikbaarheid, geen volledig haperingsvrije video.

Voor de productieboot zijn zelfstandige koude herstelkopieën van Windows en de firmware-instellingen gemaakt en met volledige hashes gecontroleerd. De bestaande driverbestanden waren al exact de geteste baseline en zijn niet herschreven. De productieconfiguratie gebruikt native weergave bij60Hz; de eerdere fysiekevouwresultaten blijven afzonderlijk bewijs, zonder nieuwe gecombineerde stressclaim.

De aanvullende fysieke video-opname bevat883frames/14,982s, met acht weinig-veranderende intervallen (maximaal1,199s). Enkele gecontroleerde beelden zijn coherent, maar bronanimatiestilstand en herhaalde renderframes zijn niet onderscheiden. De grotere bron-/renderhaperingen zijn daarmee niet algemeen opgelost.
