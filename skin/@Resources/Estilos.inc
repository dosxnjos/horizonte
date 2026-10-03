; MeterStyles comuns. Incluído depois de Variaveis.inc e Tokens.inc.
; Fonte: FontSize = px * 0.75 * #Scale# (o Rainmeter mede pt a 96 DPI).

[EstTexto]
FontFace=#FonteTexto#
FontColor=#CorOn#
AntiAlias=1

[EstDisplay]
FontFace=#FonteDisplay#
FontColor=#CorOn#
AntiAlias=1

[EstMono]
FontFace=#FonteMono#
FontColor=#CorOnV#
AntiAlias=1

; Dígito grande que rola dentro de uma máscara (Container). Centralizado no slot.
[EstDigito]
FontFace=#FonteDisplay#
FontWeight=700
StringAlign=Center
AntiAlias=1

; Chip de texto (o fundo é um Shape à parte, ajustado pelo Lua à largura do texto)
[EstChip]
FontFace=#FonteTexto#
FontWeight=600
FontSize=(13*0.75*#Scale#)
AntiAlias=1
