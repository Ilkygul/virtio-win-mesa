// scherm.exe [hz] [w h] [lijst]: set refresh rate and/or resolution of the primary display (stored in the
// registry), print the result; "lijst" prints every mode Windows offers. Output also to C:\Users\Public\meet\scherm.txt.
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
  FILE *o = fopen("C:\\Users\\Public\\meet\\scherm.txt", "w");
  DEVMODEA dm = {0}; dm.dmSize = sizeof dm;
  if (argc > 1 && !strcmp(argv[1], "lijst")) {
    for (int i = 0; EnumDisplaySettingsA(NULL, i, &dm); i++)
      if (dm.dmBitsPerPel == 32) fprintf(o ? o : stdout, "%lux%lu %lu Hz\n", dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency);
    if (o) fclose(o); return 0;
  }
  if (!EnumDisplaySettingsA(NULL, ENUM_CURRENT_SETTINGS, &dm)) { if (o) fprintf(o, "enum mislukt %lu\n", GetLastError()); return 1; }
  dm.dmFields = 0;
  if (argc > 1 && atoi(argv[1]) > 0) { dm.dmDisplayFrequency = atoi(argv[1]); dm.dmFields |= DM_DISPLAYFREQUENCY; }
  if (argc > 3) { dm.dmPelsWidth = atoi(argv[2]); dm.dmPelsHeight = atoi(argv[3]); dm.dmFields |= DM_PELSWIDTH | DM_PELSHEIGHT; }
  LONG r = dm.dmFields ? ChangeDisplaySettingsExA(NULL, &dm, NULL, CDS_UPDATEREGISTRY, NULL) : 0;
  DEVMODEA n = {0}; n.dmSize = sizeof n; EnumDisplaySettingsA(NULL, ENUM_CURRENT_SETTINGS, &n);
  char line[128]; snprintf(line, sizeof line, "resultaat %ld nu %lux%lu %lu Hz\n", r, n.dmPelsWidth, n.dmPelsHeight, n.dmDisplayFrequency);
  fputs(line, stdout); if (o) { fputs(line, o); fclose(o); }
  return r == DISP_CHANGE_SUCCESSFUL ? 0 : 1;
}
