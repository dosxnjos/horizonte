-- Horizonte\Relogio: HH:MM com dígitos que rolam, data em pt-BR e chip do próximo feriado.
-- Arquivo em UTF-16 LE com BOM (assim os acentos chegam certos aos meters).
-- Measure "mLeitor": o agenda_sync chama Recarregar() depois de gravar o agenda.json.
-- Depuração (docs/widgets.md): DebugHora=HH:MM, Forcar('HH:MM'), Quadro('13:59','14:00',0.5).

local comum, anim, mola
local G = {}          -- geometria em px de skin (já multiplicada por Scale)
local T = {}          -- tokens de cor
local A = nil         -- animação em curso
local S = {
  pronto = false,
  digitos = {'', '', '', ''},  -- o que está em repouso na tela
  hhmm = nil,                  -- hora exibida ('14:37')
  data = nil,                  -- dia exibido ('2026-10-02')
  forcada = nil,               -- hora congelada de depuração
  seg = 0,
  releitura = 60,
  animVar = true,              -- variável Animacoes
  animSistema = true,          -- agenda.json ambiente.animacoes
  pf = nil,                    -- proximoFeriado
  alfaRodape = 1,
}

local DUR_RODAPE = 0.30        -- fade da data e do chip na entrada
local ATRASO_RODAPE = 0.08
local ESCALONA_ENTRADA = 0.04  -- cascata dos dígitos na entrada

local function bang(...) SKIN:Bang(...) end
local function num(x) return string.format('%.2f', x) end

local function var(nome, padrao)
  local v = SKIN:GetVariable(nome, padrao)
  if v == nil or v == '' then return padrao end
  return v
end

local function animando() return S.animVar and S.animSistema end

-- ---------------------------------------------------------------- texto do rodapé

local function aplicarAlfa(f)
  S.alfaRodape = f
  bang('!SetOption', 'Data', 'FontColor', anim.alfa(T.onPri, 255, f))
  bang('!SetOption', 'ChipTexto', 'FontColor', anim.alfa(T.onPri, 255, f))
  if G.chipW then
    bang('!SetOption', 'ChipFundo', 'Shape', string.format(
      'Rectangle 0,0,%s,%s,%s | Fill Color %s | StrokeWidth 0',
      num(G.chipW), num(G.chipH), num(G.chipR), anim.alfa(T.onPri, T.alfaChip, f)))
  end
end

local function aplicarTextos()
  local agora = os.time()
  bang('!SetOption', 'Data', 'Text', comum.dataExtensa(agora))
  bang('!UpdateMeter', 'Data')
  local rotulo = comum.rotuloFeriado(S.pf, comum.dataIso(agora))
  if rotulo then
    -- mostrar ANTES de medir: meter oculto devolve GetW() = 0
    bang('!ShowMeter', 'ChipFundo')
    bang('!ShowMeter', 'ChipTexto')
    bang('!SetOption', 'ChipTexto', 'Text', rotulo)
    bang('!UpdateMeter', 'ChipTexto')
    local dataM, chipM = SKIN:GetMeter('Data'), SKIN:GetMeter('ChipTexto')
    local x = dataM:GetX() + dataM:GetW() + G.chipGap
    G.chipW = chipM:GetW() + 2 * G.chipPadX
    bang('!SetOption', 'ChipFundo', 'X', num(x))
    bang('!SetOption', 'ChipTexto', 'X', num(x + G.chipPadX))
    bang('!SetOption', 'ChipFundo', 'ToolTipText', comum.textoSeguro(S.pf.nome or ''))
  else
    G.chipW = nil
    bang('!HideMeter', 'ChipFundo')
    bang('!HideMeter', 'ChipTexto')
  end
  aplicarAlfa(S.alfaRodape)
end

-- ---------------------------------------------------------------- dígitos

local function separar(hhmm) return {hhmm:sub(1, 1), hhmm:sub(2, 2), hhmm:sub(4, 4), hhmm:sub(5, 5)} end

local function repouso(i, d)
  bang('!SetOption', 'D' .. i .. 'Sai', 'Text', '')
  bang('!SetOption', 'D' .. i .. 'Sai', 'Y', num(G.digY))
  bang('!SetOption', 'D' .. i .. 'Entra', 'Text', d)
  bang('!SetOption', 'D' .. i .. 'Entra', 'Y', num(G.digY))
  S.digitos[i] = d
end

local function redesenhar()
  bang('!UpdateMeter', '*')
  bang('!Redraw')
end

-- Desenha a animação A no instante s (segundos desde o início)
local function quadro(s)
  for _, it in ipairs(A.itens) do
    local e = anim.valor(mola, s - it.atraso)
    bang('!SetOption', 'D' .. it.i .. 'Sai', 'Y', num(G.digY - G.passo * e))
    bang('!SetOption', 'D' .. it.i .. 'Entra', 'Y', num(G.digY + G.passo * (1 - e)))
  end
  -- por quadro, só os meters que se mexem (os Shapes da pílula e das máscaras ficam quietos)
  bang('!UpdateMeterGroup', 'Digitos')
  if A.rodape then
    aplicarAlfa(anim.saida((s - ATRASO_RODAPE) / DUR_RODAPE))
    bang('!UpdateMeter', 'Data')
    bang('!UpdateMeter', 'ChipTexto')
    bang('!UpdateMeter', 'ChipFundo')
  end
  bang('!Redraw')
end

local function terminar()
  if not A then return end
  for _, it in ipairs(A.itens) do repouso(it.i, it.para) end
  if A.rodape then aplicarAlfa(1) end
  A = nil
  bang('!CommandMeasure', 'mAT', 'Stop 1')
  redesenhar()
end

-- itens: {{i = slot, de = 'x', para = 'y', atraso = s}}; rodape: também faz o fade da data
local function montar(itens, rodape)
  local dur = 0
  for _, it in ipairs(itens) do
    bang('!SetOption', 'D' .. it.i .. 'Sai', 'Text', it.de)
    bang('!SetOption', 'D' .. it.i .. 'Entra', 'Text', it.para)
    S.digitos[it.i] = it.para
    if mola.dur + it.atraso > dur then dur = mola.dur + it.atraso end
  end
  if rodape and ATRASO_RODAPE + DUR_RODAPE > dur then dur = ATRASO_RODAPE + DUR_RODAPE end
  return {itens = itens, rodape = rodape, dur = dur}
end

local function animar(itens, rodape)
  terminar()
  if #itens == 0 and not rodape then return end
  if not animando() then
    for _, it in ipairs(itens) do repouso(it.i, it.para) end
    if rodape then aplicarAlfa(1) end
    redesenhar()
    return
  end
  A = montar(itens, rodape)
  A.t0 = os.clock()
  quadro(0)
  bang('!CommandMeasure', 'mAT', 'Execute 1')
end

local function horaAgora()
  return S.forcada or comum.hhmm(os.time())
end

local function trocarHora(h)
  local novos, itens = separar(h), {}
  for i = 1, 4 do
    if novos[i] ~= S.digitos[i] then
      itens[#itens + 1] = {i = i, de = S.digitos[i], para = novos[i], atraso = 0}
    end
  end
  S.hhmm = h
  animar(itens, false)
end

local function checar()
  local h = horaAgora()
  if h ~= S.hhmm then trocarHora(h) end
  local hoje = comum.dataIso(os.time())
  if hoje ~= S.data then
    S.data = hoje
    aplicarTextos()
    redesenhar()
  end
end

-- ---------------------------------------------------------------- agenda.json

local function ler(forcar)
  S.leitor.caminho = comum.caminhoAgenda()  -- !SetVariable DebugAgenda vale sem refresh
  local d, mudou = S.leitor:ler(forcar)
  if not d or not mudou then return end
  S.pf = d.proximoFeriado
  S.animSistema = not (type(d.ambiente) == 'table' and d.ambiente.animacoes == false)
  if S.pronto then
    aplicarTextos()
    redesenhar()
  end
  comum.log('info', 'agenda lida; feriado=' .. tostring(type(S.pf) == 'table' and S.pf.data or 'nenhum'))
end

-- ---------------------------------------------------------------- ciclo do Rainmeter

local function seguro(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    if comum then comum.log('erro', err) else print('Horizonte Relogio: ' .. tostring(err)) end
  end
end

function Initialize()
  seguro(function()
    local carregar = dofile(SKIN:GetVariable('@') .. 'Lua\\carregar.lua')
    comum = carregar('comum')
    anim = carregar('anim')
    comum.iniciar('Relogio')
    mola = anim.nomeada('rolagem')

    local sc = tonumber(var('Scale', '1')) or 1
    G.digY = (tonumber(var('DigY', '-14')) or -14) * sc
    G.passo = (tonumber(var('DigPasso', '123')) or 123) * sc
    G.chipGap = 12 * sc
    G.chipPadX = 12 * sc
    G.chipH = 28 * sc
    G.chipR = (tonumber(var('RaioChip', '10')) or 10) * sc
    T.onPri = var('CorOnPri', '0,33,27')
    T.alfaChip = tonumber(var('AlfaChip', '36')) or 36

    S.animVar = var('Animacoes', '1') ~= '0'
    S.releitura = tonumber(var('ReleituraS', '60')) or 60
    local dh = var('DebugHora', '')
    if dh:match('^%d%d:%d%d$') then S.forcada = dh end

    S.leitor = comum.leitor(comum.caminhoAgenda(), {schemaVersion = 1})
    S.alfaRodape = 0
    ler(true)
  end)
end

-- Entrada: os quatro dígitos sobem em cascata e a data aparece em fade. Uma vez por carga.
function Entrada()
  seguro(function()
    local h = horaAgora()
    S.hhmm = h
    S.data = comum.dataIso(os.time())
    S.alfaRodape = 0
    aplicarTextos()
    local novos, itens = separar(h), {}
    for i = 1, 4 do itens[i] = {i = i, de = '', para = novos[i], atraso = (i - 1) * ESCALONA_ENTRADA} end
    animar(itens, true)
  end)
end

function Update()
  -- Initialize falhou (erro já no log do Rainmeter): não repete o erro a cada segundo
  if not comum then return '' end
  seguro(function()
    if not S.pronto then
      S.pronto = true
      Entrada()
      return
    end
    if not A then checar() end
    S.seg = S.seg + 1
    if S.seg >= S.releitura then
      S.seg = 0
      ler(false)
    end
  end)
  return S.hhmm or ''
end

-- Passo do ActionTimer (~16 ms pedidos; o tempo real vem de os.clock)
function Passo()
  seguro(function()
    if not A then
      bang('!CommandMeasure', 'mAT', 'Stop 1')
      return
    end
    local s = os.clock() - A.t0
    if s >= A.dur then terminar() else quadro(s) end
  end)
end

-- Chamado pelo agenda_sync depois de gravar o agenda.json
function Recarregar()
  seguro(ler, true)
end

-- Depuração: congela a hora (Forcar('13:59')) e volta à hora real (Forcar('')). Anima a troca.
function Forcar(hhmm)
  seguro(function()
    if hhmm and hhmm:match('^%d%d:%d%d$') then S.forcada = hhmm else S.forcada = nil end
    terminar()
    -- assenta os dígitos (um Quadro() pode ter deixado algum no meio do caminho)
    for i = 1, 4 do repouso(i, S.digitos[i]) end
    checar()
    redesenhar()
  end)
end

-- Depuração: desenha um quadro parado da rolagem de 'de' para 'para' na fração p (0..1) da mola.
-- A hora fica congelada em 'para' até Forcar('').
function Quadro(de, para, p)
  seguro(function()
    terminar()
    local a, b, itens = separar(de), separar(para), {}
    for i = 1, 4 do
      repouso(i, a[i])
      if a[i] ~= b[i] then itens[#itens + 1] = {i = i, de = a[i], para = b[i], atraso = 0} end
    end
    A = montar(itens, false)
    S.forcada, S.hhmm = para, para
    quadro(tonumber(p) * mola.dur)
    A = nil
  end)
end
