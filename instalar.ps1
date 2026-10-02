<#
.SYNOPSIS
  Instala o helper da agenda do Horizonte: venv (uv sync) e a tarefa agendada \Horizonte\AgendaSync.

.DESCRIPTION
  Pode rodar de novo quantas vezes quiser: atualiza o venv e substitui a tarefa.
  Não toca em credenciais nem em dados (%LOCALAPPDATA%\Horizonte). Rodar em primeiro plano:
    powershell -NoProfile -File instalar.ps1
  -ComSkin liga também a pasta skin\ do repo na pasta de skins do Rainmeter (fase 2).
  -SemDisparar registra a tarefa sem rodar o primeiro ciclo.
#>
[CmdletBinding()]
param(
    [switch]$ComSkin,
    [switch]$SemDisparar
)

$ErrorActionPreference = 'Stop'
$Repo = $PSScriptRoot
$TaskPath = '\Horizonte\'
$TaskName = 'AgendaSync'

function Escrever([string]$msg) { Write-Host "[horizonte] $msg" }

function Atualizar-Venv {
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        throw 'uv não encontrado no PATH. Instale: https://docs.astral.sh/uv/getting-started/installation/'
    }
    Push-Location $Repo
    try {
        & uv sync --quiet
        if ($LASTEXITCODE -ne 0) { throw "uv sync falhou (código $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
    $pyw = Join-Path $Repo '.venv\Scripts\pythonw.exe'
    if (-not (Test-Path $pyw)) { throw "pythonw.exe não apareceu em .venv\Scripts depois do uv sync" }
    Escrever 'venv atualizado'
    return $pyw
}

function Novo-GatilhoEvento([string]$caminhoLog, [string]$filtro, [string]$atraso) {
    # Register-ScheduledTask não tem cmdlet para gatilho de evento: monta a classe CIM à mão
    $cls = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
    $t = New-CimInstance -CimClass $cls -ClientOnly
    $t.Enabled = $true
    $t.Delay = $atraso
    $t.Subscription = "<QueryList><Query Id=`"0`" Path=`"$caminhoLog`"><Select Path=`"$caminhoLog`">$filtro</Select></Query></QueryList>"
    return $t
}

function Registrar-Tarefa([string]$pyw) {
    $usuario = "$env:USERDOMAIN\$env:USERNAME"
    $acao = New-ScheduledTaskAction -Execute $pyw -Argument '-m agenda_sync sync' -WorkingDirectory $Repo

    $gatilhos = @(
        # 1. logon
        (New-ScheduledTaskTrigger -AtLogOn -User $usuario),
        # 2. a cada 10 min, sem fim (sem -RepetitionDuration = indefinido; [TimeSpan]::MaxValue falha)
        (New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 10)),
        # 3. volta do sono; o atraso dá tempo de a rede subir, senão o 1º ciclo sai "offline"
        (Novo-GatilhoEvento 'System' "*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]" 'PT1M'),
        # 4. rede conectada (troca de Wi-Fi, cabo, VPN)
        (Novo-GatilhoEvento 'Microsoft-Windows-NetworkProfile/Operational' '*[System[EventID=10000]]' 'PT15S')
    )

    # Sem AllowStartIfOnBatteries/DontStopIfGoingOnBatteries o Windows nunca roda na bateria
    $cfg = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

    # Interactive: roda na sessão do usuário logado, a única que enxerga o Gerenciador de Credenciais.
    # S4U/serviço faria pessoal e corporativo voltarem "sem_credencial".
    $quem = New-ScheduledTaskPrincipal -UserId $usuario -LogonType Interactive -RunLevel Limited

    $tarefa = New-ScheduledTask -Action $acao -Trigger $gatilhos -Settings $cfg -Principal $quem `
        -Description 'Horizonte: baixa as agendas, expande recorrências e grava %LOCALAPPDATA%\Horizonte\agenda.json'
    Register-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -InputObject $tarefa -Force | Out-Null
    Escrever "tarefa $TaskPath$TaskName registrada (logon, 10 min, volta do sono, rede)"
}

function Pasta-DeSkins {
    $ini = Join-Path $env:APPDATA 'Rainmeter\Rainmeter.ini'
    if (Test-Path $ini) {
        # Rainmeter.ini é UTF-16: Get-Content lê pelo BOM
        $linha = Get-Content $ini | Where-Object { $_ -match '^\s*SkinPath\s*=' } | Select-Object -First 1
        if ($linha) {
            $valor = ($linha -split '=', 2)[1].Trim()
            if ($valor) { return $valor.TrimEnd('\') }
        }
    }
    return (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins')
}

function Ligar-Skin {
    $origem = Join-Path $Repo 'skin'
    if (-not (Test-Path $origem)) {
        Escrever 'skin\ ainda não existe no repo (fase 2): nada a ligar'
        return
    }
    $destino = Join-Path (Pasta-DeSkins) 'Horizonte'
    if (Test-Path $destino) {
        $item = Get-Item $destino -Force
        if ($item.LinkType -eq 'Junction') {
            Escrever 'skin já ligada (junction existente)'
            return
        }
        Escrever "já existe uma pasta Horizonte de verdade em Skins: não mexo nela. Apague à mão e rode de novo."
        return
    }
    try {
        New-Item -ItemType Junction -Path $destino -Target $origem | Out-Null
        Escrever 'skin ligada por junction'
    } catch {
        # disco sem NTFS ou política que barra junction: cópia (precisa rodar de novo a cada mudança)
        Copy-Item $origem $destino -Recurse
        Escrever 'junction falhou: skin copiada (rode instalar de novo depois de mudar a skin)'
    }
    $rm = 'C:\Program Files\Rainmeter\Rainmeter.exe'
    if ((Test-Path $rm) -and (Get-Process Rainmeter -ErrorAction SilentlyContinue)) {
        & $rm '!RefreshApp'
    }
}

$pyw = Atualizar-Venv
Registrar-Tarefa $pyw
if ($ComSkin) { Ligar-Skin }
if (-not $SemDisparar) {
    Start-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName
    Escrever 'primeiro ciclo disparado; confira com: uv run agenda-sync status'
}
Escrever 'pronto. Para desfazer: powershell -NoProfile -File desinstalar.ps1'
