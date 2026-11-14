# Release notes — fold-classic3d-20261114-r1

**Beperkte productie-demo daadwerkelijk getest.** Gebruiksklare appgerichte workaround; algemene DWM-/WinUI-glitches blijven open.

Deze release bevat een vaste Windows ARM64 D3D11-demo met privé framekopie, een launcher met een klassieke titelbalk voor uitsluitend het eigen demovenster en een installer voor één bureaubladsnelkoppeling. De bron, het buildscript en het pakketmanifest ondersteunen herleidbaarheid naar de bestaande geteste EXE.

## Bestaande test-VM-uitkomst

- 15 kubussen, 960×640 client, private-copy1, vsync1; 1 s opwarming en 30 s meting.
- 1807 presents / 30,010548 s = 60,212 API-fps; natuurlijke exit0 en lege stderr.
- Alle 1844 actieve opgenomen frames hadden 15 kubussen en nul felmagenta captionpixels in de gecontroleerde ROI; klassieke titeltekst leesbaar.
- Alleen de eigen HWND-policy veranderde; het clientoppervlak bleef gelijk. Andere vensters en drivers werden door de launcher niet aangepast.

De productievariant maakt het pakket verplaatsbaar via `$PSScriptRoot` en heeft een nieuwe snelkoppelinginstaller. De productievariant is daarna afzonderlijk via de geïnstalleerde snelkoppeling gestart en volledig opgenomen. De ontdekdeadline is na de waargenomen14,3s-koude start gericht van12naar30s verlengd; alle eigendomscontroles zijn behouden.

## Afbakening

De bestaande KMD `1CA…` en native UMD `3EEF…` blijven vereisten; beide strikte synchronisatiemarkers blijven aan. Er wordt geen driver gebundeld, herbouwd of geïnstalleerd. C4-videoviewhistorie en CPU-decodemetingen zijn afzonderlijke informatie en geen runtimevrijgave van de complete gepubliceerde driverbranch.

Dit is geen algemene DWM-, driver-, caption- of Direct3D-reparatie. De private-copy-route vermijdt de bekende fout in rechtstreeks gedeeld tekenen alleen voor deze app. Caption-/WinUI-corruptie kan in andere vensters blijven optreden. De C26/C27-bufferwijzigingen gaven geen captionwinst en horen niet bij deze release. Diagnostische hostpatches worden niet als correctheidsfix aangeboden.

API-fps is geen fysieke schermfrequentie; de opname is geen volledige pixelvrijgave. Er is geen nieuwe gelijktijdige video-/3D-/vouwstresstest voor dit pakket geclaimd.

## Productie-uitkomst

- Geteste ongewijzigde bestaande KMD1CA/UMD3EEF/EC7A40; GPU-foutcode0, dezelfde DWM vóór/na. Geen driverinstallatie nodig.
- Geldige per-windowpolicy1→0, client960×640, natuurlijk procesexit0/lege stderr.
- 1810 presents/30,013541s =60,306API-fps; max Present-interval21,418ms.
- Alle1832actieve opgenomen frames bevatten15kubussen, zonder felmagenta titelbalkpixels; leesbare bijgewerkte klassieke tekst.22startupframes en18finaldesktopframes apart.
- YouTubeAV11080p60:58,981browserfps/30drops, daadwerkelijke D3D11/QTI-hardwaredecode; WindowsCPU12,285%/Edge4,993% (20s binnen playback). Fysieke15s-opname bevat acht weinig-veranderende intervallen, maximaal1,199s; bronstilstand versus renderherhaling onbekend. Geen volledig haperingsvrije videovrijgave.
- Eerste12s-launchercontrole en eerste videometing met latecookiedialoog afgewezen; alleen geldige vervolgmetingen ondersteunen bovenstaande cijfers. Een UI-klik zonder workload is evenmin een proef.
- Productiebackups volledig geverifieerd; bestaande driverbestanden behouden, native60Hzconfig ingesteld. Test-VM blijft afzonderlijk bewaard.

De release bevat de bewezen demo-EXE als los pakketasset, plus bron/buildscript/launcher/manifest. De gepubliceerde C4-videobron is een afzonderlijke beoordeelde bronwijziging; er is geen nieuwe volledige driverbranch gebouwd of als releasebinary aangeboden.
