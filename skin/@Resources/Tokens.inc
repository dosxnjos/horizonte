[Variables]
; Tokens do tema ativo. Um arquivo por tema: Tokens-<tema>.inc, escolhido por Tema no Variaveis.inc.
; Este arquivo vem depois do Variaveis.inc (o #Tema# precisa existir antes deste @Include).
@IncludeTema=#@#Tokens-#Tema#.inc

; Contrato do anel Claude e alertas de sistema: NÃO mudam com o tema (herdado do tray, roadmap § 1)
ClaudeOk=48,164,108
ClaudeAlerta=245,166,35
ClaudeCritico=229,72,77
ClaudeVelho=116,118,132
; trilho das barras das contas (#46464E, o mesmo da bandeja)
ClaudeTrilho=70,70,78
; Saúde de fonte (Agenda): âmbar = dado velho/offline, vermelho = precisa de ação (--warn/--bad do protótipo)
CorAlerta=245,166,35
CorCritico=229,72,77

; Fontes nativas do Windows 11
FonteDisplay=Segoe UI Variable Display
FonteTexto=Segoe UI Variable Text
FonteMono=Cascadia Mono
