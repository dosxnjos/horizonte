# Converte os arquivos do skin\ para UTF-16 LE com BOM (idempotente).
# Alvo: todo .ini/.inc e todo .lua, exceto os ASCII carregados por dofile (json.lua, carregar.lua),
# que o Lua 5.1 so le em bytes crus. A ferramenta Write grava UTF-8 em arquivo novo e, em arquivo
# que ja era UTF-16, pode gravar UTF-16 LE SEM BOM: os dois casos sao tratados (o segundo so ganha
# o BOM; reencodar como se fosse UTF-8 duplicaria os zeros e quebraria o arquivo).
#   powershell -NoProfile -File tools\skin-utf16.ps1
#   -Pasta <dir> troca o alvo (teste em pasta temporaria).
param([string]$Pasta = (Join-Path (Split-Path -Parent $PSScriptRoot) 'skin'))
$skin = (Resolve-Path $Pasta).Path
$asciiDofile = @('json.lua', 'carregar.lua')

function Test-Utf16SemBom([byte[]]$b) {
    # UTF-16 LE de texto latino: byte alto zero nas posicoes impares. Amostra os primeiros 64 pares.
    if ($b.Length -lt 4 -or ($b.Length % 2) -ne 0) { return $false }
    $n = [Math]::Min($b.Length / 2, 64); $zeros = 0
    for ($i = 0; $i -lt $n; $i++) { if ($b[2 * $i + 1] -eq 0 -and $b[2 * $i] -ne 0) { $zeros++ } }
    return ($zeros -ge [Math]::Ceiling($n * 0.9))
}

Get-ChildItem -Path $skin -Recurse -File -Include *.ini, *.inc, *.lua | ForEach-Object {
    if ($asciiDofile -contains $_.Name) { return }
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { return }
    $rel = $_.FullName
    if ($rel.StartsWith($skin + '\')) { $rel = $rel.Substring($skin.Length + 1) }
    if (Test-Utf16SemBom $bytes) {
        $txt = [Text.Encoding]::Unicode.GetString($bytes)
        [IO.File]::WriteAllText($_.FullName, $txt, [Text.Encoding]::Unicode)
        "bom: $rel (ja era UTF-16 LE sem BOM)"
        return
    }
    $txt = [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($_.FullName, $txt, [Text.Encoding]::Unicode)
    "utf16: $rel"
}
