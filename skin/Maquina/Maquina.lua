-- Horizonte\Maquina: anéis de CPU, RAM, GPU e discos.
-- Arquivo em UTF-16 LE com BOM (assim os acentos chegam certos aos meters).
-- Regras (docs/widgets.md § Máquina):
--   * neutro em repouso (CorOnV); âmbar a partir de 85 sustentado 10 s, vermelho a partir de 95 (RAM 93)
--     sustentado 30 s; disco âmbar com < 15 % livre e vermelho com < 8 %; histerese na saída;
--   * número e arco usam o MESMO valor mostrado, quantizado (CPU/GPU de 5 em 5, RAM de 1 em 1, disco em
--     GB inteiros) com zona morta: parado, a tela só redesenha quando esse valor muda;
--   * movimento: varredura do anel na entrada (escalonada) e na troca de faixa; dígitos rolam quando o
--     número muda; nada de tween a 1 Hz; na bateria, leitura a cada BateriaCadenciaS e sem animação.
--   * GPU por amostra (2 s a cada 10 s): o contador "GPU Engine" custa caro enquanto configurado.
-- Depuração: Forcar('cpu', 96), Forcar('C:', 40), ForcarBateria('1'), Entrada(), Log(1), Contar().

local comum, anim, molaVarre, molaRola, molaBoing, molaEsp
local sc = 1
local T = {}          -- cores
local L = {}          -- geometria (px de skin)
local G = {}          -- anéis visíveis, em ordem
local S = {
  pronto = false,
  animVar = true,
  animSistema = true,
  bateria = false,
  forcaBateria = nil,
  forcado = {},
  hover = nil,
  ultLeitura = -1e9,
  ultDisco = -1e9,
  ultGpu = -1e9,
  ultBateria = -1e9,
  seg = 0,
  releitura = 60,
  cpuReserva = false,
  cpuZeros = 0,
  cpuHist = {},
  ativos = 0,         -- anéis com animação em curso
}

local DUR_COR = 0.40
local ESCALONA = 0.06
local DISCO_S = 30          -- leitura dos discos (mudam devagar)
local GPU_S = 10            -- uma amostra da GPU a cada 10 s (contador caro; ver gpuCaro)
local GPU_S_BATERIA = 30
local GPU_AMOSTRA = 2       -- segundos apontando para a GPU antes de ler
local CPU_MEDIA = 5         -- leituras na média móvel da CPU
local BATERIA_S = 10        -- consulta da tomada
local MAX_DISCOS = 3
local GIB = 1024 ^ 3

-- Faixas: carga (0..100) a partir da qual sobe; tempo sustentado (s); quanto abaixo do limiar a
-- carga precisa ficar, e por quanto tempo, para descer.
local FAIXAS = {
  cpu = {sobe = {85, 95}, tempo = {10, 30}, hist = 5, desce = 5},
  gpu = {sobe = {85, 95}, tempo = {10, 30}, hist = 5, desce = 5},
  ram = {sobe = {85, 93}, tempo = {10, 30}, hist = 3, desce = 5},
  -- disco: carga = % usado. < 15 % livre = > 85 % usado; < 8 % livre = > 92 % usado. Imediato.
  disco = {sobe = {85.0001, 92.0001}, tempo = {0, 0}, hist = 1, desce = 0},
}

local function bang(...) SKIN:Bang(...) end
local function num(x) return string.format('%.2f', x) end

local function var(nome, padrao)
  local v = SKIN:GetVariable(nome, padrao)
  if v == nil or v == '' then return padrao end
  return v
end

local function animando() return S.animVar and S.animSistema and not S.bateria end

local function valorMedida(nome)
  local m = SKIN:GetMeasure(nome)
  if not m then return 0 end
  return m:GetValue() or 0
end

local function limitar(x, a, b) if x < a then return a elseif x > b then return b end return x end

-- ---------------------------------------------------------------- texto dos números

-- "61" / "80" / "1,8" (TB) e a unidade. nil = sem leitura ("–").
local function formatar(g, v)
  if v == nil then return '–', '' end
  if g.tipo == 'disco' then
    if v >= 999.5 then return (string.format('%.1f', v / 1024):gsub('%.', ',')), 'TB' end
    return tostring(math.floor(v + 0.5)), 'GB'
  end
  return tostring(math.floor(v + 0.5)), '%'
end

local function caracteres(s)
  local t = {}
  for c in s:gmatch('[%z\1-\127\194-\244][\128-\191]*') do t[#t + 1] = c end
  return t
end

-- ---------------------------------------------------------------- desenho do anel

local function ponto(a, r)
  local th = math.rad(a)
  return L.c + r * math.sin(th), L.c - r * math.cos(th)
end

local function arco(a0, a1, cor, larg)
  local x0, y0 = ponto(a0, L.r)
  local x1, y1 = ponto(a1, L.r)
  return string.format('Arc %s,%s,%s,%s,%s,%s,0,0,%d | StrokeWidth %s | Stroke Color %s | '
    .. 'StrokeStartCap Round | StrokeEndCap Round | Fill Color 0,0,0,0',
    num(x0), num(y0), num(x1), num(y1), num(L.r), num(L.r), (a1 - a0) > 180 and 1 or 0, num(larg), cor)
end

local VAZIO = 'Rectangle 0,0,0,0 | StrokeWidth 0 | Fill Color 0,0,0,0'

local function circulo(cor)
  return string.format('Ellipse %s,%s,%s | StrokeWidth %s | Stroke Color %s | Fill Color 0,0,0,0',
    num(L.c), num(L.c), num(L.r), num(L.sw), cor)
end

-- Disco de fundo: círculo em repouso; "cookie" (amp 0,05) e "sol" (0,1) nas faixas de alerta.
local function disco(g, cor, amp, rot)
  if math.abs(amp) < 0.002 then
    bang('!SetOption', g.anel, 'Shape', string.format('Ellipse %s,%s,%s | Fill Color %s | StrokeWidth 0',
      num(L.c), num(L.c), num(L.R), cor))
    return
  end
  local p, N, rr = {}, 72, math.rad(rot)
  for i = 0, N do
    local th = i / N * 2 * math.pi
    local r = L.R * (1 + amp * math.cos(10 * (th - rr)))
    local x, y = L.c + r * math.sin(th), L.c - r * math.cos(th)
    p[#p + 1] = (i == 0 and '' or 'LineTo ') .. num(x) .. ',' .. num(y)
  end
  bang('!SetOption', g.anel, 'Disco', table.concat(p, ' | ') .. ' | ClosePath 1')
  bang('!SetOption', g.anel, 'Shape', 'Path Disco | Fill Color ' .. cor .. ' | StrokeWidth 0')
end

-- f: fração do arco (0..1); cor 'R,G,B'; amp/rot: forma do disco.
local function desenharAnel(g, f, cor, amp, rot)
  f = limitar(f, 0, 1)
  disco(g, cor .. ',38', amp, rot)
  local trilho, ind = cor .. ',61', cor .. ',255'
  if f < 0.004 then
    bang('!SetOption', g.anel, 'Shape2', circulo(trilho))
    bang('!SetOption', g.anel, 'Shape3', VAZIO)
  elseif f > 0.996 then
    bang('!SetOption', g.anel, 'Shape2', VAZIO)
    bang('!SetOption', g.anel, 'Shape3', circulo(ind))
  else
    local a1 = f * 360
    local t0, t1 = a1 + L.vaoGraus, 360 - L.vaoGraus
    if t1 - t0 > 1.08 then
      bang('!SetOption', g.anel, 'Shape2', arco(t0, t1, trilho, L.sw))
    else
      bang('!SetOption', g.anel, 'Shape2', VAZIO)
    end
    bang('!SetOption', g.anel, 'Shape3', arco(0, a1, ind, L.sw))
  end
end

-- ---------------------------------------------------------------- dígitos

-- Posição dos dígitos (centro de cada um, relativo à máscara) e da unidade para um texto.
local function layout(g, chars, uni)
  local n = #chars
  local uw = (uni ~= '' and (L.uniW[uni] or 0) + L.uniGap) or 0
  local esq = L.c - (n * L.dig + uw) / 2
  local xs = {}
  -- k = 1 é o dígito da direita
  for k = 1, n do xs[k] = esq + (n - k + 0.5) * L.dig end
  return xs, esq + n * L.dig + L.uniGap
end

local function porDireita(chars, k) return chars[#chars - k + 1] end

-- Repouso: só os "E" com texto, na linha.
local function digitosRepouso(g)
  local chars = caracteres(g.texto)
  local xs, ux = layout(g, chars, g.uni)
  for k = 1, 3 do
    local e, s = g.n .. 'E' .. k, g.n .. 'S' .. k
    bang('!SetOption', s, 'Text', '')
    bang('!SetOption', e, 'Text', porDireita(chars, k) or '')
    bang('!SetOption', e, 'X', num(xs[k] or 0))
    bang('!SetOption', e, 'Y', num(L.digY))
  end
  bang('!SetOption', g.u, 'Text', g.uni)
  bang('!SetOption', g.u, 'X', num(g.x + ux))
end

-- Prepara a rolagem de 'de' para 'para' (texto + unidade). dir 1 = sobe (valor maior), -1 = desce.
local function digitosMontar(g, de, para, uni, dir)
  local a, b = caracteres(de), caracteres(para)
  local xa = layout(g, a, g.uni)
  local xb, ux = layout(g, b, uni)
  local rola = {}
  local mesmoTam = (#a == #b) and (uni == g.uni)
  for k = 1, 3 do
    local ca, cb = porDireita(a, k) or '', porDireita(b, k) or ''
    local s, e = g.n .. 'S' .. k, g.n .. 'E' .. k
    if ca ~= cb or not mesmoTam then
      bang('!SetOption', s, 'Text', ca)
      bang('!SetOption', s, 'X', num(xa[k] or 0))
      bang('!SetOption', e, 'Text', cb)
      bang('!SetOption', e, 'X', num(xb[k] or 0))
      rola[#rola + 1] = k
    else
      bang('!SetOption', s, 'Text', '')
      bang('!SetOption', e, 'Text', cb)
      bang('!SetOption', e, 'X', num(xb[k] or 0))
      bang('!SetOption', e, 'Y', num(L.digY))
    end
  end
  bang('!SetOption', g.u, 'Text', uni)
  bang('!SetOption', g.u, 'X', num(g.x + ux))
  return {ks = rola, dir = dir}
end

local function digitosQuadro(g, R, e)
  for _, k in ipairs(R.ks) do
    bang('!SetOption', g.n .. 'S' .. k, 'Y', num(L.digY - R.dir * L.passo * e))
    bang('!SetOption', g.n .. 'E' .. k, 'Y', num(L.digY + R.dir * L.passo * (1 - e)))
  end
end

-- ---------------------------------------------------------------- estado visual de um anel

local function corFaixa(e)
  if e == 2 then return T.critico elseif e == 1 then return T.alerta end
  return T.neutro
end
local AMP = {[0] = 0, 0.05, 0.1}

-- Em lote (entrada, leitura de vários anéis no mesmo tick), só marca: um !Redraw por anel deixava a
-- tela mostrar um quadro com metade dos anéis já trocados (visto na rajada da entrada).
local function redesenhar(g)
  if S.lote then
    S.lote[#S.lote + 1] = g.i
    return
  end
  bang('!UpdateMeterGroup', 'G' .. g.i)
  bang('!Redraw')
end

local function emLote(fn)
  S.lote = {}
  local ok, err = pcall(fn)
  local sujos = S.lote
  S.lote = nil
  for _, i in ipairs(sujos) do bang('!UpdateMeterGroup', 'G' .. i) end
  if #sujos > 0 then bang('!Redraw') end
  if not ok then error(err, 0) end
end

-- Valores de uma animação no instante s (segundos desde o início dela, já descontado o atraso).
local function avaliar(A, s)
  local v = {}
  v.f = A.f0 + (A.f1 - A.f0) * anim.valor(molaVarre, s)
  v.cor = A.c0 == A.c1 and A.c1 or anim.cor(A.c0, A.c1, anim.saida(s / DUR_COR)):gsub(',%d+$', '')
  v.amp = A.a0 + (A.a1 - A.a0) * anim.valor(molaBoing, s)
  v.rot = A.r0 + (A.r1 - A.r0) * anim.valor(molaEsp, s)
  v.dig = anim.valor(molaRola, s)
  return v
end

local function aplicarQuadro(g, v)
  g.vis = {f = v.f, cor = v.cor, amp = v.amp, rot = v.rot}
  desenharAnel(g, v.f, v.cor, v.amp, v.rot)
  if g.A.rola then digitosQuadro(g, g.A.rola, v.dig) end
end

local function terminarAnel(g)
  local A = g.A
  if not A then return end
  g.A = nil
  S.ativos = S.ativos - 1
  g.vis = {f = A.f1, cor = A.c1, amp = A.a1, rot = A.r1}
  desenharAnel(g, A.f1, A.c1, A.a1, A.r1)
  digitosRepouso(g)
end

-- O ActionTimer avisa no log ("'ActionList1' is currently running") a cada Execute com a lista já
-- rodando: S.timer guarda se ela está rodando, e só um anel liga.
local function ligarTimer()
  if S.timer then return end
  S.timer = true
  S.ligouEm = os.clock()
  bang('!CommandMeasure', 'mAT', 'Execute 1')
end

local function pararTimerSeOcioso()
  if S.ativos <= 0 then
    S.ativos = 0
    if S.timer then
      S.timer = false
      bang('!CommandMeasure', 'mAT', 'Stop 1')
    end
  end
end

-- Leva o anel ao alvo (g.alvo: f, faixa, texto, uni). varrer = arco sai do 0 (entrada/troca de faixa).
local function mostrar(g, varrer, atraso)
  local alvo = g.alvo
  local cor1, amp1 = corFaixa(alvo.faixa), AMP[alvo.faixa]
  local rot1 = g.vis.rot + ((g.faixaVis ~= nil and alvo.faixa ~= g.faixaVis) and (alvo.faixa > g.faixaVis and 18 or -18) or 0)
  local deTexto, deUni = g.texto, g.uni
  local dir = 1
  if g.valorVis and alvo.valor and alvo.valor < g.valorVis then dir = -1 end

  -- Número de sistema muda o tempo todo: a rolagem por leitura custava 2 a 5 pontos de CPU parado
  -- (revisão de 03/10, ~370 passos de animação/min). Só anima entrada (varrer) e troca de faixa;
  -- a leitura comum troca seco.
  local trocaFaixa = g.faixaVis ~= nil and alvo.faixa ~= g.faixaVis
  if not animando() or (not varrer and not trocaFaixa) then
    if g.A then g.A = nil; S.ativos = S.ativos - 1; pararTimerSeOcioso() end
    g.texto, g.uni, g.valorVis, g.faixaVis = alvo.texto, alvo.uni, alvo.valor, alvo.faixa
    g.vis = {f = alvo.f, cor = cor1, amp = amp1, rot = rot1}
    desenharAnel(g, alvo.f, cor1, amp1, rot1)
    digitosRepouso(g)
    redesenhar(g)
    return
  end

  -- interrompe o que estava em curso a partir do ponto atual
  if g.A then
    local v = avaliar(g.A, os.clock() - g.A.t0)
    g.vis = {f = v.f, cor = v.cor, amp = v.amp, rot = v.rot}
    g.A = nil
    S.ativos = S.ativos - 1
    digitosRepouso(g)
  end

  local A = {
    t0 = os.clock() + (atraso or 0),
    f0 = varrer and 0 or alvo.f, f1 = alvo.f,
    c0 = g.vis.cor, c1 = cor1,
    a0 = g.vis.amp, a1 = amp1,
    r0 = g.vis.rot, r1 = rot1,
  }
  if deTexto ~= alvo.texto or deUni ~= alvo.uni then
    A.rola = digitosMontar(g, deTexto, alvo.texto, alvo.uni, dir)
  end
  g.texto, g.uni, g.valorVis, g.faixaVis = alvo.texto, alvo.uni, alvo.valor, alvo.faixa
  A.dur = math.max(varrer and molaVarre.dur or 0, A.c0 ~= A.c1 and DUR_COR or 0,
    A.a0 ~= A.a1 and molaBoing.dur or 0, A.r0 ~= A.r1 and molaEsp.dur or 0, A.rola and molaRola.dur or 0)
  if A.dur <= 0 then
    -- nada a animar (ex.: só o arco andou): desenho seco
    g.vis = {f = A.f1, cor = A.c1, amp = A.a1, rot = A.r1}
    desenharAnel(g, A.f1, A.c1, A.a1, A.r1)
    digitosRepouso(g)
    redesenhar(g)
    return
  end
  g.A = A
  S.ativos = S.ativos + 1
  aplicarQuadro(g, avaliar(A, 0))
  redesenhar(g)
  ligarTimer()
end

-- ---------------------------------------------------------------- faixas (histerese por relógio)

local function atualizarFaixa(g, carga, agora)
  local F = FAIXAS[g.fx]
  local e = g.faixa
  -- subir: cada limiar tem o próprio "desde quando"
  for n = 1, 2 do
    if carga >= F.sobe[n] then
      g.desde[n] = g.desde[n] or agora
    else
      g.desde[n] = nil
    end
  end
  local alvo = 0
  for n = 1, 2 do
    if g.desde[n] and agora - g.desde[n] >= F.tempo[n] then alvo = n end
  end
  if alvo > e then
    g.abaixo = nil
    return alvo
  end
  -- descer: carga abaixo do limiar da faixa atual menos a histerese, por F.desce segundos
  if e > 0 and carga < F.sobe[e] - F.hist then
    g.abaixo = g.abaixo or agora
    if agora - g.abaixo >= F.desce then
      g.abaixo = nil
      local novo = 0
      if e == 2 and carga >= F.sobe[1] - F.hist then novo = 1 end
      return novo
    end
  else
    g.abaixo = nil
  end
  return e
end

-- ---------------------------------------------------------------- leitura

local function lerCpu()
  local u = valorMedida('mCpu')
  local r = valorMedida('mCpuReserva')
  if not S.cpuReserva then
    -- contador ausente (Windows sem "Processor Information"): o UsageMonitor devolve 0 para sempre
    if u <= 0 and r > 3 then S.cpuZeros = S.cpuZeros + 1 else S.cpuZeros = 0 end
    if S.cpuZeros >= 5 then
      S.cpuReserva = true
      comum.log('erro', 'contador "% Processor Utility" sem leitura: usando Measure=CPU (aprox.)')
    end
  end
  local v = limitar(S.cpuReserva and r or u, 0, 100)
  -- média das CPU_MEDIA últimas leituras: o "% Processor Utility" pula 10 a 20 pontos de um segundo
  -- para o outro com a máquina ocupada (visto em 02/10), e cada pulo de 5 em 5 é uma rolagem. A faixa
  -- (10 s / 30 s sustentados) quase não sente o atraso de ~2 s.
  local h = S.cpuHist
  h[#h + 1] = v
  if #h > CPU_MEDIA then table.remove(h, 1) end
  local soma = 0
  for _, x in ipairs(h) do soma = soma + x end
  return soma / #h
end

-- Valor mostrado com zona morta: só troca quando o bruto se afasta mais de 0,6 passo do atual.
local function quantizar(g, bruto)
  local q = math.floor(bruto / g.passo + 0.5) * g.passo
  if g.valorAlvo == nil then return q end
  if math.abs(bruto - g.valorAlvo) < g.passo * 0.6 then return g.valorAlvo end
  return q
end

local function legendaRam(usado)
  return (string.format('%.1fG', usado / GIB):gsub('%.', ','))
end

-- Lê um anel e devolve (carga 0..100 para a faixa, valor mostrado, fração do arco, extras)
local function lerAnel(g)
  local fz = S.forcado[g.chave]
  if g.tipo == 'cpu' then
    local v = fz or lerCpu()
    local q = quantizar(g, v)
    return v, q, q / 100
  elseif g.tipo == 'gpu' then
    local v = fz or S.gpuValor
    if v == nil then return 0, nil, 0 end
    local q = quantizar(g, v)
    return v, q, q / 100
  elseif g.tipo == 'ram' then
    local total = valorMedida('mRamTotal')
    local usado = valorMedida('mRam')
    if total <= 0 then return 0, nil, 0 end
    local v = fz or (usado / total * 100)
    if fz then usado = total * fz / 100 end
    local q = quantizar(g, v)
    g.sub = legendaRam(total * q / 100)
    g.tip = string.format('RAM: %s de %s em uso (%d%%)', legendaRam(usado), legendaRam(total), math.floor(v + 0.5))
    return v, q, q / 100
  else
    local livre, total = valorMedida(g.medida), valorMedida(g.medida .. 'Total')
    if total <= 0 then
      g.tip = g.letra .. ' indisponível'
      g.dica, g.sub = g.tip, ''
      return 0, nil, 0
    end
    g.sub = 'livres'
    local gb = livre / GIB
    if fz then gb = fz end
    local totGb = total / GIB
    gb = limitar(gb, 0, totGb)
    local q = quantizar(g, gb)
    local usado = (1 - gb / totGb) * 100
    g.tip = string.format('%s (%s): %d GB livres de %d GB, %d%% usado', g.rotulo, g.letra,
      math.floor(gb + 0.5), math.floor(totGb + 0.5), math.floor(usado + 0.5))
    g.dica = string.format('%s %d de %d GB livres', g.letra, math.floor(gb + 0.5), math.floor(totGb + 0.5))
    return usado, q, 1 - q / totGb
  end
end

local function legendas(g)
  if g.sub ~= g.subVis then
    g.subVis = g.sub
    bang('!SetOption', g.subm, 'Text', g.sub or '')
  end
  if g.tip ~= g.tipVis then
    g.tipVis = g.tip
    bang('!SetOption', g.hit, 'ToolTipText', g.tip or '')
    bang('!UpdateMeter', g.hit)
  end
end

local function processar(g, agora)
  local carga, valor, f = lerAnel(g)
  g.faixa = atualizarFaixa(g, carga, agora)
  g.valorAlvo = valor
  local texto, uni = formatar(g, valor)
  local trocaFaixa = g.faixa ~= g.faixaVis
  legendas(g)
  if not S.pronto then
    g.alvo = {f = f, faixa = g.faixa, texto = texto, uni = uni, valor = valor}
    return
  end
  if texto == g.texto and uni == g.uni and not trocaFaixa then
    -- o valor mostrado não mudou: não redesenha (o arco segue o mesmo valor quantizado)
    return
  end
  g.alvo = {f = f, faixa = g.faixa, texto = texto, uni = uni, valor = valor}
  comum.log('info', string.format('%s %s%s -> %s%s (bruto %.1f, faixa %d)', g.chave, g.texto, g.uni,
    texto, uni, carga, g.faixa))
  mostrar(g, trocaFaixa, 0)
end

-- O contador "GPU Engine" tem centenas de instâncias, e o UsageMonitor consulta a categoria numa
-- thread própria enquanto algum measure apontar para ela, lido ou não, ligado ou não: custava ~3,5
-- pontos de um núcleo e ~10 MB parado (medido em 02/10). Então o mGpu fica no contador barato do mCpu
-- e só aponta para a GPU durante a amostra.
local function gpuCaro()
  bang('!SetOption', 'mGpu', 'Category', '')
  bang('!SetOption', 'mGpu', 'Counter', '')
  bang('!SetOption', 'mGpu', 'Name', '')
  bang('!SetOption', 'mGpu', 'Alias', 'GPU')
  bang('!SetOption', 'mGpu', 'Index', '0')
  bang('!UpdateMeasure', 'mGpu')
end
local function gpuBarato()
  bang('!SetOption', 'mGpu', 'Alias', '')
  bang('!SetOption', 'mGpu', 'Category', 'Processor Information')
  bang('!SetOption', 'mGpu', 'Counter', '% Processor Utility')
  bang('!SetOption', 'mGpu', 'Name', '_Total')
  bang('!UpdateMeasure', 'mGpu')
end

-- Chamada a cada tick: liga a amostra a cada GPU_S (GPU_S_BATERIA na bateria) e, passados
-- GPU_AMOSTRA s, lê e volta ao contador barato. Devolve true quando há valor novo em S.gpuValor.
local function amostrarGpu(agora)
  if S.gpuDesde then
    if agora - S.gpuDesde < GPU_AMOSTRA - 0.05 then return false end
    bang('!UpdateMeasure', 'mGpu')
    S.gpuValor = limitar(valorMedida('mGpu'), 0, 100)
    comum.log('info', string.format('gpu %.1f (amostra de %.1f s)', S.gpuValor, agora - S.gpuDesde))
    gpuBarato()
    S.gpuDesde, S.ultGpu = nil, agora
    return true
  end
  if agora - S.ultGpu >= (S.bateria and GPU_S_BATERIA or GPU_S) - 0.05 then
    gpuCaro()
    S.gpuDesde = agora
  end
  return false
end

local function processarGpu(agora)
  for _, g in ipairs(G) do
    if g.tipo == 'gpu' then processar(g, agora) end
  end
end

local function lerSistema(agora, discos)
  comum.log('info', string.format('leitura%s%s', discos and ' +discos' or '', S.bateria and ' (bateria)' or ''))
  for _, x in ipairs({'mCpu', 'mCpuReserva', 'mRam', 'mRamTotal'}) do bang('!UpdateMeasure', x) end
  if discos then
    for _, g in ipairs(G) do
      if g.tipo == 'disco' then
        bang('!UpdateMeasure', g.medida)
        bang('!UpdateMeasure', g.medida .. 'Total')
      end
    end
  end
  emLote(function()
    for _, g in ipairs(G) do
      if (g.tipo == 'disco' and discos) or g.tipo == 'cpu' or g.tipo == 'ram' then
        processar(g, agora)
      end
    end
  end)
end

local function lerBateria()
  if S.forcaBateria ~= nil then return S.forcaBateria end
  local dbg = var('DebugBateria', '')
  if dbg == '1' then return true elseif dbg == '0' then return false end
  bang('!UpdateMeasure', 'mBateria')
  return valorMedida('mBateria') == 0
end

-- ---------------------------------------------------------------- hover

local function textoSeguro(s)
  return comum.textoSeguro(tostring(s or ''):gsub('[%[%]#]', ''))
end

local function tamanho(bytes)
  if bytes >= GIB then return (string.format('%.1f GB', bytes / GIB):gsub('%.', ',')) end
  return string.format('%d MB', math.floor(bytes / 1024 ^ 2 + 0.5))
end

local function atualizarDica()
  local g = S.hover and G[S.hover]
  local t = ''
  if g then
    if g.tipo == 'cpu' then
      bang('!UpdateMeasure', 'mTopCpu')
      local m = SKIN:GetMeasure('mTopCpu')
      local nome, v = m and m:GetStringValue() or '', m and m:GetValue() or 0
      -- O UsageMonitor já entrega "% Processor Time" do processo dividido pelos núcleos lógicos
      -- (medido em 02/10: grep a 100 % de um núcleo = 7,0 com 14 threads). Não dividir de novo.
      if nome ~= '' and v > 0 then
        t = string.format('%s %d%%', textoSeguro(nome), math.floor(v + 0.5))
      else
        t = '…'
      end
      if S.cpuReserva then t = t .. ' (aprox.)' end
    elseif g.tipo == 'ram' then
      bang('!UpdateMeasure', 'mTopRam')
      local m = SKIN:GetMeasure('mTopRam')
      local nome, v = m and m:GetStringValue() or '', m and m:GetValue() or 0
      if nome ~= '' and v > 0 then
        t = 'maior: ' .. textoSeguro(nome) .. ' ' .. tamanho(v)
      else
        t = '…'
      end
    elseif g.tipo == 'disco' then
      t = g.dica or g.tip or ''
    end
  end
  if t ~= S.dica then
    S.dica = t
    bang('!SetOption', 'Dica', 'Text', t)
    bang('!UpdateMeter', 'Dica')
    bang('!Redraw')
  end
end

-- O UsageMonitor consulta a categoria do measure mesmo com ele desligado: em repouso o measure aponta
-- para o contador barato do mCpu e só vira Alias=CPU/RAM (categoria Process) durante o hover.
local topLigado = {}
local function topLigar(m, alias)
  if topLigado[m] then return end
  topLigado[m] = true
  bang('!SetOption', m, 'Category', '')
  bang('!SetOption', m, 'Counter', '')
  bang('!SetOption', m, 'Name', '')
  bang('!SetOption', m, 'Alias', alias)
  bang('!SetOption', m, 'Index', '1')
  bang('!SetOption', m, 'Blacklist', '_Total|Idle')
  bang('!SetOption', m, 'Rollup', '1')
  bang('!EnableMeasure', m)
end
local function topDesligar(m)
  if not topLigado[m] then return end
  topLigado[m] = nil
  bang('!SetOption', m, 'Alias', '')
  bang('!SetOption', m, 'Index', '0')
  bang('!SetOption', m, 'Blacklist', '')
  bang('!SetOption', m, 'Rollup', '0')
  bang('!SetOption', m, 'Category', 'Processor Information')
  bang('!SetOption', m, 'Counter', '% Processor Utility')
  bang('!SetOption', m, 'Name', '_Total')
  -- uma atualização com as opções de repouso faz o plugin largar a categoria Process
  bang('!UpdateMeasure', m)
  bang('!DisableMeasure', m)
end

function Hover(i)
  if not comum then return end
  local ok, err = pcall(function()
    i = tonumber(i)
    local g = G[i]
    if not g then return end
    S.hover = i
    if g.tipo == 'cpu' then topLigar('mTopCpu', 'CPU') end
    if g.tipo == 'ram' then topLigar('mTopRam', 'RAM') end
    atualizarDica()
  end)
  if not ok then comum.log('erro', err) end
end

function Sair(i)
  if not comum then return end
  local ok, err = pcall(function()
    if S.hover ~= tonumber(i) then return end
    S.hover = nil
    topDesligar('mTopCpu')
    topDesligar('mTopRam')
    atualizarDica()
  end)
  if not ok then comum.log('erro', err) end
end

-- ---------------------------------------------------------------- montagem

local function listaDiscos()
  local t, visto = {}, {}
  for p in tostring(var('Discos', 'C:')):gmatch('[^,;|%s]+') do
    local letra = p:match('^(%a)')
    if letra then
      letra = letra:upper() .. ':'
      if not visto[letra] and #t < MAX_DISCOS then
        visto[letra] = true
        t[#t + 1] = letra
      end
    end
  end
  return t
end

local function novoAnel(i, tipo, chave, cap)
  local g = {
    i = i, tipo = tipo, chave = chave, fx = (tipo == 'disco') and 'disco' or tipo,
    passo = (tipo == 'cpu' or tipo == 'gpu') and 5 or 1,
    anel = 'Anel' .. i, masc = 'Masc' .. i, n = 'N' .. i, u = 'U' .. i,
    subm = 'Sub' .. i, hit = 'Hit' .. i,
    faixa = 0, faixaVis = nil, desde = {}, texto = '', uni = '', cap = cap,
    vis = {f = 0, cor = T.neutro, amp = 0, rot = 0},
  }
  g.capm = 'Cap' .. i
  return g
end

local function montar()
  G = {}
  G[1] = novoAnel(1, 'cpu', 'cpu', 'CPU')
  G[2] = novoAnel(2, 'ram', 'ram', 'RAM')
  G[3] = novoAnel(3, 'gpu', 'gpu', 'GPU')
  local clique = {'["taskmgr"]', '["resmon"]', '["taskmgr"]'}
  for n, letra in ipairs(listaDiscos()) do
    local i = 3 + n
    local g = novoAnel(i, 'disco', letra, var('RotuloDisco' .. letra:sub(1, 1), letra))
    g.letra, g.rotulo, g.medida, g.sub = letra, g.cap, 'mDisco' .. n, 'livres'
    bang('!SetOption', g.medida, 'Drive', letra)
    bang('!SetOption', g.medida .. 'Total', 'Drive', letra)
    bang('!EnableMeasure', g.medida)
    bang('!EnableMeasure', g.medida .. 'Total')
    clique[i] = letra == 'C:' and '["ms-settings:storagesense"]' or ('["' .. letra .. '\\"]')
    G[i] = g
  end
  local n = #G
  local W = 2 * L.pad + n * L.col + (n - 1) * L.vao
  bang('!SetOption', 'Cartao', 'Shape', string.format('Rectangle 0,0,%s,%s,%s | Fill Color %s,255 | StrokeWidth 0',
    num(W), num(L.h), num(L.raio), T.s))
  bang('!SetOption', 'Dica', 'X', num(W - L.pad))
  for _, g in ipairs(G) do
    local esq = L.pad + (g.i - 1) * (L.col + L.vao)
    g.x = esq + L.col / 2 - L.anel / 2
    g.cx = esq + L.col / 2
    for _, m in ipairs({g.anel, g.masc, g.u, g.capm, g.subm, g.hit}) do bang('!ShowMeter', m) end
    bang('!SetOption', g.anel, 'X', num(g.x))
    bang('!SetOption', g.masc, 'X', num(g.x))
    bang('!SetOption', g.u, 'Y', num(L.uniY))
    bang('!SetOption', g.capm, 'X', num(g.cx))
    bang('!SetOption', g.capm, 'Text', g.cap)
    bang('!SetOption', g.subm, 'X', num(g.cx))
    bang('!SetOption', g.subm, 'Text', g.sub or '')
    bang('!SetOption', g.hit, 'X', num(esq))
    bang('!SetOption', g.hit, 'LeftMouseUpAction', clique[g.i])
    desenharAnel(g, 0, T.neutro, 0, 0)
  end
  -- anéis que sobraram (lista de discos menor): escondidos e com os measures desligados
  for i = #G + 1, 6 do
    for _, p in ipairs({'Anel', 'Masc', 'U', 'Cap', 'Sub', 'Hit'}) do bang('!HideMeter', p .. i) end
    for k = 1, 3 do bang('!HideMeter', 'N' .. i .. 'S' .. k); bang('!HideMeter', 'N' .. i .. 'E' .. k) end
  end
  for n = #G - 3 + 1, MAX_DISCOS do
    bang('!DisableMeasure', 'mDisco' .. n)
    bang('!DisableMeasure', 'mDisco' .. n .. 'Total')
  end
end

-- Largura do '%' / 'GB' / 'TB' medida no próprio meter (mostrado: oculto mede 0)
local function medirUnidades()
  L.uniW = {}
  for _, u in ipairs({'%', 'GB', 'TB'}) do
    bang('!ShowMeter', 'U1')
    bang('!SetOption', 'U1', 'Text', u)
    bang('!UpdateMeter', 'U1')
    L.uniW[u] = SKIN:GetMeter('U1'):GetW()
  end
  bang('!SetOption', 'U1', 'Text', '')
end

-- ---------------------------------------------------------------- agenda.json (só ambiente.animacoes)

local function lerAgenda(forcar)
  S.leitor.caminho = comum.caminhoAgenda()
  local d, mudou = S.leitor:ler(forcar)
  if not d or not mudou then return end
  S.animSistema = not (type(d.ambiente) == 'table' and d.ambiente.animacoes == false)
end

-- ---------------------------------------------------------------- ciclo do Rainmeter

local function seguro(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    if comum then comum.log('erro', err) else print('Horizonte Maquina: ' .. tostring(err)) end
  end
end

function Initialize()
  seguro(function()
    local carregar = dofile(SKIN:GetVariable('@') .. 'Lua\\carregar.lua')
    comum = carregar('comum')
    anim = carregar('anim')
    comum.iniciar('Maquina')
    molaVarre = anim.nomeada('rolagem')       -- crítica, ~350 ms: varredura do arco
    molaRola = anim.nomeada('rolagem')        -- dígitos, igual ao Relógio
    molaBoing = anim.nomeada('boing', 0.01)   -- forma do disco (cookie/sol)
    molaEsp = anim.nomeada('espacial', 0.01)  -- giro do disco na troca de faixa

    sc = tonumber(var('Scale', '1')) or 1
    -- geometria do protótipo (viewBox 128 desenhado em 68 px: fator 68/128)
    local k = 68 / 128
    L.pad, L.col, L.vao, L.anel, L.h = 24 * sc, 66 * sc, 6 * sc, 68 * sc, 187 * sc
    L.raio = (tonumber(var('RaioCartao', '32')) or 32) * sc
    L.c = 64 * k * sc
    L.r = 50 * k * sc
    L.sw = 11 * k * sc
    L.R = (50 - 5.5 - 7) * k * sc
    -- vão de 4 px entre as pontas redondas do indicador e do trilho
    L.vaoGraus = (11 + 4 * 128 / 68) / (2 * math.pi * 50) * 360
    L.dig = 10.9 * sc          -- avanço de um dígito a 20 px (letter-spacing -0,03 em)
    L.uniGap = 0.5 * sc
    L.digY = -2.4 * sc         -- Y do dígito dentro da máscara (ajustado contra o protótipo)
    L.uniY = 92 * sc           -- '%'/'GB' na mesma linha de base dos dígitos
    L.passo = 22 * sc          -- 1,1 em

    T.neutro = var('CorOnV', '166,191,185')
    T.alerta = var('CorAlerta', '245,166,35')
    T.critico = var('CorCritico', '229,72,77')
    T.s = var('CorS', '21,48,45')

    S.animVar = var('Animacoes', '1') ~= '0'
    S.releitura = tonumber(var('ReleituraS', '60')) or 60
    S.cadBateria = tonumber(var('BateriaCadenciaS', '5')) or 5
    S.leitor = comum.leitor(comum.caminhoAgenda(), {schemaVersion = 1})
    lerAgenda(true)

    medirUnidades()
    montar()
    S.bateria = lerBateria()
    S.ultBateria = os.clock()
    lerSistema(os.clock(), true)
    S.ultLeitura, S.ultDisco = os.clock(), os.clock()
    bang('!UpdateMeter', '*')
    bang('!Redraw')
  end)
end

-- Entrada: os anéis varrem do zero até o valor, escalonados; os números rolam de baixo.
function Entrada()
  seguro(function()
    for n, g in ipairs(G) do
      if g.A then g.A = nil; S.ativos = S.ativos - 1 end
      g.texto, g.uni, g.valorVis, g.faixaVis = '', '', nil, nil
      g.vis = {f = 0, cor = corFaixa(g.alvo and g.alvo.faixa or 0), amp = 0, rot = 0}
      digitosRepouso(g)
      desenharAnel(g, 0, g.vis.cor, 0, 0)
      S.lote = {}
      local ok, err = pcall(function()
        if g.alvo then mostrar(g, true, (n - 1) * ESCALONA) end
      end)
      S.lote = nil
      if not ok then comum.log('erro', err) end
    end
    -- um redesenho só, com todos os anéis já no quadro 0
    bang('!UpdateMeter', '*')
    bang('!Redraw')
  end)
end

function Update()
  if not comum then return '' end
  seguro(function()
    local agora = os.clock()
    if not S.pronto then
      -- a entrada espera a primeira amostra da GPU (~2 s), para todos os anéis varrerem juntos
      if not amostrarGpu(agora) and S.gpuValor == nil then return end
      processarGpu(agora)
      S.pronto = true
      Entrada()
      return
    end
    if amostrarGpu(agora) then emLote(function() processarGpu(agora) end) end
    -- vigia: anel animando e nenhum passo há mais de 0,5 s = a lista do ActionTimer acabou sozinha
    if S.ativos > 0 and S.timer and agora - math.max(S.ultPasso or 0, S.ligouEm or 0) > 0.5 then
      comum.log('erro', 'ActionTimer parado com anel animando: religando')
      S.timer = false
      ligarTimer()
    end
    if agora - S.ultBateria >= BATERIA_S then
      S.ultBateria = agora
      local b = lerBateria()
      if b ~= S.bateria then
        S.bateria = b
        comum.log('info', b and 'bateria: leitura lenta, sem animação' or 'tomada: leitura a 1 s')
      end
    end
    local cad = S.bateria and S.cadBateria or 1
    if agora - S.ultLeitura >= cad - 0.05 then
      -- salto de relógio (> 2x a cadência, mínimo 10 s: o PC dormiu ou o Rainmeter travou). O os.clock
      -- conta o sono; um "acima desde" de antes do sono viraria alerta sustentado na hora. Recomeça a
      -- contagem dos tempos sustentados (roadmap, Fase 2: retomada do sono).
      if agora - S.ultLeitura > math.max(2 * cad, 10) and S.ultLeitura > 0 then
        for _, g in ipairs(G) do g.desde = {}; g.abaixo = nil end
        comum.log('info', string.format('salto de relógio de %.0f s: tempos sustentados zerados', agora - S.ultLeitura))
      end
      local discos = agora - S.ultDisco >= DISCO_S
      if discos then S.ultDisco = agora end
      S.ultLeitura = agora
      lerSistema(agora, discos)
    end
    if S.hover then atualizarDica() end
    S.seg = S.seg + 1
    if S.seg >= S.releitura then
      S.seg = 0
      lerAgenda(false)
    end
  end)
  return ''
end

-- Passo do ActionTimer (30 ms pedidos, como na Agenda: cada quadro repinta a janela inteira; o tempo
-- real vem de os.clock)
function Passo()
  seguro(function()
    S.passos = (S.passos or 0) + 1
    S.ultPasso = os.clock()
    if S.ativos <= 0 then
      S.timer = false
      S.ociosos = (S.ociosos or 0) + 1
      bang('!CommandMeasure', 'mAT', 'Stop 1')
      return
    end
    local agora = os.clock()
    local mexeu = false
    for _, g in ipairs(G) do
      local A = g.A
      if A then
        local s = agora - A.t0
        if s >= A.dur then
          terminarAnel(g)
          bang('!UpdateMeterGroup', 'G' .. g.i)
          mexeu = true
        elseif s >= 0 then
          aplicarQuadro(g, avaliar(A, s))
          bang('!UpdateMeterGroup', 'G' .. g.i)
          mexeu = true
        end
      end
    end
    if mexeu then bang('!Redraw') end
    pararTimerSeOcioso()
  end)
end

function Recarregar()
  seguro(lerAgenda, true)
end

-- Depuração: Forcar('cpu', 96) / Forcar('ram', 88) / Forcar('gpu', 41) / Forcar('C:', 40) (GB livres).
-- Forcar('cpu', '') volta ao real. A faixa respeita os mesmos tempos sustentados (10 s / 30 s).
function Forcar(chave, valor)
  seguro(function()
    chave = tostring(chave or '')
    if chave:match('^%a:?$') then chave = chave:sub(1, 1):upper() .. ':' end
    S.forcado[chave] = tonumber(valor)
    if chave == 'cpu' then S.cpuHist = {} end
    local agora = os.clock()
    for _, g in ipairs(G) do
      if g.chave == chave then
        if g.tipo == 'disco' then
          bang('!UpdateMeasure', g.medida)
          bang('!UpdateMeasure', g.medida .. 'Total')
        end
        processar(g, agora)
      end
    end
  end)
end

-- Depuração: Log(1) liga o log de rotina (widget.log) sem refresh; Log(0) desliga.
function Log(v)
  if comum then comum.debug = tostring(v) == '1' end
end

-- Depuração: Contar() grava no widget.log (sempre, como 'erro' não é) quantos passos do ActionTimer
-- rodaram desde a última chamada e quantos foram ociosos (prova de que o timer para sozinho).
function Contar()
  if not comum then return end
  local d = comum.debug
  comum.debug = true
  comum.log('info', string.format('passos %d, ociosos %d, ativos %d, timer %s',
    S.passos or 0, S.ociosos or 0, S.ativos, tostring(S.timer)))
  comum.debug = d
  S.passos, S.ociosos = 0, 0
end

-- Depuração: ForcarBateria('1') simula a bateria, ('0') a tomada, ('') volta ao real.
function ForcarBateria(v)
  seguro(function()
    if v == '1' or v == 1 then S.forcaBateria = true
    elseif v == '0' or v == 0 then S.forcaBateria = false
    else S.forcaBateria = nil end
    S.bateria = lerBateria()
    comum.log('info', 'bateria forçada: ' .. tostring(S.forcaBateria))
  end)
end
