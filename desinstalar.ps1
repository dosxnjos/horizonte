<#
.SYNOPSIS
  Desfaz o instalar.ps1: remove a tarefa agendada \Horizonte\AgendaSync e a junction da skin.

.DESCRIPTION
  Sem parâmetro, preserva dados (%LOCALAPPDATA%\Horizonte) e credenciais: reinstalar volta de onde parou.
  -Tudo apaga também os endereços secretos do Gerenciador de Credenciais e os arquivos do Horizonte
  em %LOCALAPPDATA%\Horizonte (config.toml, agenda.json, cache, sync.log). Subpastas que não são do
  helper (por exemplo spike\) ficam.
    powershell -NoProfile -File desinstalar.ps1 [-Tudo]
#>
[CmdletBinding()]
param(
    [switch]$Tudo
)

$ErrorActionPreference = 'Stop'
$Repo = $PSScriptRoot
$TaskPath = '\Horizonte\'
$TaskName = 'AgendaSync'

function Escrever([string]$msg) { Write-Host "[horizonte] $msg" }

# 1. tarefa agendada
if (Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Confirm:$false
    Escrever "tarefa $TaskPath$TaskName removida"
} else {
    Escrever 'tarefa não estava registrada'
}
# a pasta \Horizonte\ do Agendador sai só se ficou vazia
try {
    $svc = New-Object -ComObject Schedule.Service
    $svc.Connect()
    $pasta = $svc.GetFolder('\Horizonte')
    if ($pasta.GetTasks(1).Count -eq 0 -and $pasta.GetFolders(0).Count -eq 0) {
        $svc.GetFolder('\').DeleteFolder('Horizonte', 0)
        Escrever 'pasta \Horizonte do Agendador removida'
    }
} catch {
    # pasta já não existe
}

# 2. junction da skin (só se for junction: pasta de verdade nunca é apagada aqui)
$ini = Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini'
$skins = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins'
if (Test-Path $ini) {
    $linha = Get-Content $ini | Where-Object { $_ -match '^\s*SkinPath\s*=' } | Select-Object -First 1
    if ($linha -and ($linha -split '=', 2)[1].Trim()) { $skins = ($linha -split '=', 2)[1].Trim().TrimEnd('\') }
}
$skin = Join-Path $skins 'Horizonte'
if (Test-Path $skin) {
    $item = Get-Item $skin -Force
    if ($item.LinkType -eq 'Junction') {
        # Delete() na junction remove só o link, nunca o conteúdo do repo
        $item.Delete()
        Escrever 'junction da skin removida'
    } else {
        Escrever 'Skins\Horizonte é uma pasta de verdade (cópia): não apaguei; remova à mão se quiser'
    }
}

if (-not $Tudo) {
    Escrever 'dados e credenciais preservados (use -Tudo para apagar)'
    exit 0
}

# 3. credenciais: pela mesma biblioteca que gravou (o nome do alvo no Windows é detalhe do keyring)
$py = Join-Path $Repo '.venv\Scripts\python.exe'
if (Test-Path $py) {
    $codigo = @'
import keyring
from keyring.errors import PasswordDeleteError
for apelido in ("pessoal", "corporativo"):
    try:
        keyring.delete_password("Horizonte", apelido)
        print(f"credencial {apelido}: apagada")
    except PasswordDeleteError:
        print(f"credencial {apelido}: ausente")
'@
    & $py -c $codigo
} else {
    Escrever 'venv ausente: apague à mão as entradas "Horizonte" em Painel de Controle > Gerenciador de Credenciais > Credenciais do Windows'
}

# 4. dados locais do helper
$dados = Join-Path $env:LOCALAPPDATA 'Horizonte'
if (Test-Path $dados) {
    foreach ($nome in @('config.toml', 'agenda.json', 'sync.log', 'sync.log.1', 'sync.lock', 'cache')) {
        $alvo = Join-Path $dados $nome
        if (Test-Path $alvo) { Remove-Item $alvo -Recurse -Force }
    }
    if (-not (Get-ChildItem $dados -Force)) {
        Remove-Item $dados -Force
        Escrever "pasta de dados removida"
    } else {
        Escrever "arquivos do helper removidos; ficaram em %LOCALAPPDATA%\Horizonte só pastas que não são dele"
    }
}
Escrever 'desinstalado'
