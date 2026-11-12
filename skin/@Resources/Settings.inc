[Variables]
; ============================================================================================
;  HORIZONTE - your settings
; ============================================================================================
;  Edit the values below, save, then right-click any Horizonte widget > "Refresh skin"
;  (or Rainmeter tray icon > "Refresh all").
;
;  Rules of the Rainmeter .inc format:
;   - a comment is a line that STARTS with ";". A ";" in the middle of a value is part of the value;
;   - keep this file in UTF-16 LE (Notepad: "Save as" > Encoding "UTF-16 LE") if you type accents;
;   - reinstalling or upgrading with the .rmskin keeps the values you set here.
;
;  Variable names are in Portuguese (the suite was born in Brazil); the meaning is next to each one.
; ============================================================================================


; --------------------------------------------------------------------------------------------
;  LANGUAGE
; --------------------------------------------------------------------------------------------
; en = English, pt = Portuguese (Brazil). Dates, labels and menus follow it. Times are 24 h.
Idioma=en


; --------------------------------------------------------------------------------------------
;  DEMO MODE
; --------------------------------------------------------------------------------------------
; 1 = sample agenda and sample Claude usage, generated around today's date. Nothing to set up.
; 0 = your real data: the agenda comes from the agenda_sync helper and the Claude widget from
;     the claude-usage-tray app (both optional, see "REAL DATA" at the end of this file).
;     The clock and the Machine widget always show real values.
Demo=1


; --------------------------------------------------------------------------------------------
;  LOOK
; --------------------------------------------------------------------------------------------
; Theme (Tema):
;   expressivo = solid tonal cards, the Day card changes shape and color with its state (default)
;   pistache   = the same design in a light pistachio scheme
;   crepusculo = "Dusk": dark translucent cards with one amber accent, the clock floats over the wallpaper
Tema=expressivo

; Size multiplier for every widget (1 = default; 1.25 = 25% bigger).
Scale=1

; Animations (Animacoes): 1 = short transitions on change (rolling digits, sweeping rings,
; shape morph); 0 = everything changes instantly. They also turn off when Windows
; "Animation effects" is off (reported by the agenda helper).
Animacoes=1


; --------------------------------------------------------------------------------------------
;  AGENDA AND DAY
; --------------------------------------------------------------------------------------------
; Private mode (Privado): 1 = every event title shows as "Compromisso" (appointment).
; The lock icon on the Agenda widget toggles this and saves it here for you.
Privado=0

; How many events the Agenda lists before "mais N eventos" (more N events). Lower it if the
; card goes behind the taskbar on a short screen.
MaxItems=8


; --------------------------------------------------------------------------------------------
;  MACHINE (Maquina)
; --------------------------------------------------------------------------------------------
; Drives with their own ring, comma separated, up to 3. Example: C:,D:
Discos=C:
; Fixed label per drive letter (RotuloDisco<letter>). Without one, the letter is shown.
RotuloDiscoC=SSD
RotuloDiscoD=Data


; --------------------------------------------------------------------------------------------
;  CLAUDE
; --------------------------------------------------------------------------------------------
; Account nicknames, by the account number in the claude-usage-tray snapshot (1, 2, 3...).
; Shown instead of "account N". E-mails and organization names are never displayed.
; (Demo mode uses its own sample names.) Remove the ";" to use them:
; ApelidoConta1=personal
; ApelidoConta2=work

; Where the claude-usage-tray .exe lives. Clicking the "tray stopped" notice launches it.
; Always use environment variables (%USERPROFILE%, %LOCALAPPDATA%), never a typed user name.
TrayExe=%USERPROFILE%\claude-usage-tray\Claude Usage Tray.exe

; Advanced: read another file in the same snapshot.json format instead of the tray's
; (FonteClaude). Empty = the tray's own file.
FonteClaude=


; --------------------------------------------------------------------------------------------
;  REAL DATA (optional, only when Demo=0)
; --------------------------------------------------------------------------------------------
;  Agenda (Relogio holiday chip, Dia, Agenda): the widgets never touch the network. They read
;    %LOCALAPPDATA%\Horizonte\agenda.json, written by "agenda_sync", a small Python helper from
;    the GitHub repo (dosxnjos/horizonte). It downloads your calendars' private iCal addresses,
;    expands recurring events and writes the file every 10 minutes. The private addresses are
;    stored in Windows Credential Manager, never in a skin file.
;
;  Claude: the widget only reads %LOCALAPPDATA%\claude-usage-tray\snapshot.json, written by the
;    claude-usage-tray app (GitHub: dosxnjos/claude-usage-tray). It never calls any API itself.
;
;  Without those files the widgets say so ("agenda unavailable", "tray app has no reading yet")
;  and keep working; nothing breaks.
;
;  Local.inc (optional, same folder) is read after this file: handy to keep machine-specific
;  overrides out of a shared copy. Nobody needs it.
