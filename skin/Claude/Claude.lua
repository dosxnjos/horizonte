-- Horizonte\Claude: anel da janela 5h da conta ativa + barras das contas inativas.
-- Arquivo em UTF-16 LE com BOM (assim os acentos chegam certos aos meters).
-- Regras (roadmap § 1 e docs/widgets.md § Claude):
--   * SÓ LÊ %LOCALAPPDATA%\claude-usage-tray\snapshot.json (nunca cswap nem API);
--   * anel = janela "5h" da conta Active (Get-SessionPct da bandeja: barra Label "5h", senão a primeira);
--     sem Active, a primeira conta (Get-ActiveAccount);
--   * verde < 60 ≤ âmbar < 85 ≤ vermelho; de 95 em diante o arco mostra (p-95)/5 da volta, com ponto
--     marcador (mínimo de 8°, como a bandeja);
--   * cinza só com Stale=true da bandeja ou com a bandeja parada (savedAt > TrayParadoS E processo
--     ausente); a idade (AgeS + agora - savedAt) fica sempre visível nesses casos;
--   * nome da conta = ApelidoConta<Num> ou "conta N": e-mail e Org NUNCA aparecem (nem no log).
-- Movimento: varredura do arco por mola crítica (sem overshoot no valor); o disco vira cookie/sol pela
-- mola boing (a forma quica) e gira ±18° pela espacial na troca de faixa; dígitos rolam; barras andam
-- pela mesma mola do arco; nada em laço. Parado = zero redesenho além da virada do minuto.
-- Depuração: Recarregar(), Entrada(), ForcarTray('0'|'1'|''), Esquecer(), Log(1), Contar().

local comum, anim, anelMod, AN
local molaDado, molaRola, molaBoing, molaEsp
local sc = 1
local T = {}          -- cores
local L = {}          -- geometria (px de skin)
local S = {
  animVar = true, animSistema = true,
  seg = 0, segSnap = 0, releitura = 60, releituraSnap = 20, paradoS = 150,
  snap = nil, minuto = nil, hover = false, debugTray = '',
  ativos = 0, timer = false,
}
-- estado visual do anel (o que está na tela) e animações em curso
local VIS = {f = 0, cor = nil, amp = 0, rot = 0, ponto = 0, texto = '', uni = '', forma = 0, zoom = false}
local AR = nil        -- animação do anel
local AB = nil        -- animação das barras / painel
local PAINEL = {}     -- linhas desenhadas: [j] = {chave, f, cor}
local SIG = {}        -- assinaturas do que está na tela (anel, painel, legenda, layout)

local DUR_COR = 0.40
local DUR_FADE = 0.18
local ROT = 18
local AMP = {[0] = 0, 0.05, 0.1}
local MAX_NOMES, MAX_LINHAS = 4, 8

local STATUS = {
  expired = 'token expirado',
  relogin = 're-login preciso',
  notoken = 'sem credencial salva',
  apikey = 'conta usa API key',
  offline = 'API indisponível',
  ratelimited = 'limite da API (429)',
  nodata = 'sem medição recente',
}

local function bang(...) SKIN:Bang(...) end
local num = function(x) return string.format('%.2f', x) end

local function var(nome, padrao)
  local v = SKIN:GetVariable(nome, padrao)
  if v == nil or v == '' then return padrao end
  return v
end

local function animando() return S.animVar and S.animSistema end
local function limitar(x, a, b) if x < a then return a elseif x > b then return b end return x end

-- só manda o !SetOption se o valor mudou (parado = zero trabalho)
local OPC = {}
local function opcao(meter, chave, valor)
  local k = meter .. '\0' .. chave
  if OPC[k] == valor then return end
  OPC[k] = valor
  bang('!SetOption', meter, chave, valor)
end
local function mostrarMeter(m, sim)
  local k = m .. '\0#vis'
  if OPC[k] == sim then return end
  OPC[k] = sim
  bang(sim and '!ShowMeter' or '!HideMeter', m)
end

local function caracteres(s)
  local t = {}
  for c in tostring(s):gmatch('[%z\1-\127\194-\244][\128-\191]*') do t[#t + 1] = c end
  return t
end

-- ---------------------------------------------------------------- leitura do snapshot

local function statusTexto(st)
  st = tostring(st or '')
  if st == '' or st == 'ok' then return nil end
  return STATUS[st] or 'sem dados'
end

local function nomeConta(c)
  local n = tonumber(c.Num)
  if not n then return 'conta ?' end
  n = math.floor(n)
  return var('ApelidoConta' .. n, 'conta ' .. n)
end

local function barras(c)
  local t = {}
  if type(c.Bars) == 'table' then
    for _, b in ipairs(c.Bars) do
      if type(b) == 'table' and tonumber(b.Pct) then
        t[#t + 1] = {rot = tostring(b.Label or '?'), pct = tonumber(b.Pct), reset = b.ResetsAt}
      end
    end
  end
  return t
end

-- Get-SessionPct da bandeja: a barra "5h"; senão a primeira
local function barraSessao(bs)
  for _, b in ipairs(bs) do if b.rot == '5h' then return b end end
  return bs[1]
end

local function corPct(p)
  if p >= 85 then return T.critico elseif p >= 60 then return T.alerta end
  return T.ok
end
local function faixaPct(p)
  if p >= 85 then return 2 elseif p >= 60 then return 1 end
  return 0
end

local function idadeTexto(s)
  if not s then return nil end
  local m = math.max(1, math.floor(s / 60))
  if m >= 48 * 60 then return 'há ' .. math.floor(m / 1440) .. ' dias' end
  return 'há ' .. comum.duracao(m)
end

-- "14:59" se cai hoje, "sex 14:59" se não
local function hhmmDia(t, agora)
  if comum.dataIso(t) == comum.dataIso(agora) then return comum.hhmm(t) end
  return comum.DIAS_CURTOS[os.date('*t', t).wday] .. ' ' .. comum.hhmm(t)
end

local function textoReset(iso, agora)
  if type(iso) ~= 'string' or iso == '' then return 'janela não iniciada' end
  local t = comum.epochIso(iso)
  if not t then return 'janela não iniciada' end
  if t <= agora then return 'renovou às ' .. hhmmDia(t, agora) end
  local min = math.ceil((t - agora) / 60)
  local em = (min >= 48 * 60) and (math.floor(min / 1440) .. ' dias') or comum.duracao(min)
  return 'renova ' .. hhmmDia(t, agora) .. ' (em ' .. em .. ')'
end

-- O processo da bandeja está rodando? (Measure=Process, atualizado só aqui)
local function trayVivo()
  if S.debugTray == '0' then return false elseif S.debugTray == '1' then return true end
  bang('!UpdateMeasure', 'mTray')
  local m = SKIN:GetMeasure('mTray')
  return m ~= nil and (m:GetValue() or -1) > 0
end

-- Snapshot -> estado a desenhar (sem nada de tela)
local function derivar(snap, agora)
  local E = {painelNormal = {}, painelAtiva = {}}
  local lista = {}
  if type(snap) == 'table' and type(snap.accounts) == 'table' then
    for _, c in ipairs(snap.accounts) do if type(c) == 'table' then lista[#lista + 1] = c end end
  end
  local salvo = type(snap) == 'table' and comum.epochIso(snap.savedAt) or nil
  local idadeSalvo = salvo and math.max(0, agora - salvo) or nil
  -- bandeja parada: o snapshot envelheceu E o processo sumiu (com a bandeja viva, o recuo do 429 deixa o
  -- savedAt envelhecer até 10 min sem que nada esteja errado)
  local parado = false
  if idadeSalvo == nil or idadeSalvo > S.paradoS then parado = not trayVivo() end
  E.parado = parado

  local ativa
  for _, c in ipairs(lista) do if c.Active == true then ativa = c; break end end
  ativa = ativa or lista[1]

  -- idade do dado de uma conta: AgeS da bandeja + o tempo desde que ela gravou
  local function idadeConta(c)
    if c.Stale == true then
      if tonumber(c.AgeS) == nil then return nil end
      return tonumber(c.AgeS) + (idadeSalvo or 0)
    end
    return idadeSalvo
  end
  local function cinza(c) return parado or c.Stale == true end

  -- ---------- anel
  if not ativa then
    E.texto, E.f, E.zoom, E.cor, E.forma, E.apagado = '–', 0, false, T.velho, 0, true
    E.cap = parado and idadeTexto(idadeSalvo) or ''
    E.prefixo, E.resto = '', (snap == nil) and 'bandeja ainda sem medição' or 'nenhuma conta no snapshot'
  else
    local bs = barras(ativa)
    local b = barraSessao(bs)
    local nome = nomeConta(ativa)
    local st = statusTexto(ativa.Status)
    E.nome = nome
    if not b then
      E.texto, E.f, E.zoom, E.cor, E.forma, E.apagado = '–', 0, false, T.velho, 0, true
      E.cap = parado and idadeTexto(idadeSalvo) or ''
      E.prefixo, E.resto = nome, st or 'sem dados'
    else
      local p = b.pct
      local pc = limitar(p, 0, 100)
      E.texto = tostring(math.floor(p + 0.5))
      E.zoom = pc >= 95
      E.f = E.zoom and (pc - 95) / 5 or pc / 100
      local velho = cinza(ativa)
      E.cor = velho and T.velho or corPct(pc)
      E.forma = velho and 0 or faixaPct(pc)
      E.apagado = velho
      local idade = idadeConta(ativa)
      if velho then
        -- sem AgeS (cswap antigo) não há idade: "antiga" cabe dentro do anel; a legenda explica
        E.cap = idadeTexto(idade) or 'antiga'
      else
        E.cap = ''
      end
      E.prefixo = b.rot .. ', ' .. nome
      if ativa.Stale == true then
        if idade then
          E.resto = 'sem medição nova ' .. idadeTexto(idade) .. ' (última às ' .. comum.hhmm(agora - idade) .. ')'
        else
          E.resto = 'medição antiga'
        end
      else
        E.resto = textoReset(b.reset, agora)
      end
      if st then E.resto = E.resto .. ', ' .. st end
    end
  end

  -- ---------- bandeja parada: bloco no lugar da legenda
  if parado then
    local quando = salvo and (', dados de ' .. hhmmDia(salvo, agora)) or ''
    local exe = comum.expandirAmbiente(var('TrayExe', ''))
    if exe ~= '' and comum.existe(exe) then
      E.bloco = 'bandeja parada' .. quando .. '. Clique para abrir.'
    else
      E.bloco = 'bandeja parada' .. quando .. '. Ajuste TrayExe no Local.inc para abrir por aqui.'
    end
  end

  -- ---------- coluna da direita
  -- so: nil = todas as barras; senão o conjunto de rótulos que entram ({['5h'] = true, ...})
  local function linhas(c, so)
    local out = {}
    local bs = barras(c)
    local velho = cinza(c)
    for _, b in ipairs(bs) do
      if not so or so[b.rot] then
        local pc = limitar(b.pct, 0, 100)
        out[#out + 1] = {tipo = 'linha', chave = tostring(c.Num) .. '|' .. b.rot, rot = b.rot,
          f = pc / 100, cor = velho and T.velho or corPct(pc), txt = math.floor(b.pct + 0.5) .. '%'}
      end
    end
    if #out == 0 then
      out[1] = {tipo = 'aviso', chave = tostring(c.Num) .. '|aviso', rot = statusTexto(c.Status) or 'sem dados'}
    end
    return out
  end
  local function etiqueta(c, padrao)
    if c.Stale == true then return idadeTexto(idadeConta(c)) or 'medição antiga' end
    if #barras(c) > 0 and statusTexto(c.Status) then return statusTexto(c.Status) end
    return padrao
  end

  if ativa then
    local P = E.painelAtiva
    P[#P + 1] = {tipo = 'nome', nome = nomeConta(ativa), tag = etiqueta(ativa, 'ativa')}
    for _, l in ipairs(linhas(ativa, nil)) do P[#P + 1] = l end
  end
  local inativas = {}
  for _, c in ipairs(lista) do if c ~= ativa then inativas[#inativas + 1] = c end end
  if #inativas == 0 then
    -- regra do anel (roadmap § 1): da conta ativa, em repouso, só a janela 5h. Sem inativas, a coluna
    -- repete só a 5h da ativa; 7d e Fable aparecem só no hover do anel (pedido explícito do mouse).
    if ativa then
      local P = E.painelNormal
      P[#P + 1] = {tipo = 'nome', nome = nomeConta(ativa), tag = etiqueta(ativa, 'ativa')}
      local bs = barraSessao(barras(ativa))   -- a mesma barra do anel (5h; senão a primeira)
      for _, l in ipairs(linhas(ativa, {[bs and bs.rot or '5h'] = true})) do P[#P + 1] = l end
    end
  else
    local P = E.painelNormal
    -- até MAX_NOMES contas; passando disso, as MAX_NOMES-1 primeiras e uma linha "mais N contas"
    local cabe = (#inativas > MAX_NOMES) and (MAX_NOMES - 1) or #inativas
    for i = 1, cabe do
      local c = inativas[i]
      P[#P + 1] = {tipo = 'nome', nome = nomeConta(c), tag = etiqueta(c, 'inativa')}
      for _, l in ipairs(linhas(c, {['5h'] = true, ['7d'] = true})) do P[#P + 1] = l end
    end
    if cabe < #inativas then
      P[#P + 1] = {tipo = 'nome', nome = 'mais ' .. (#inativas - cabe) .. ' contas', tag = ''}
    end
  end
  return E
end

-- ---------------------------------------------------------------- anel

local function corAnel(cor) return cor end

local function desenharAnel(f, cor, amp, rot, ponto, zoom)
  local shape, caminho = AN:disco(cor .. ',38', amp, rot)
  if caminho then opcao('Anel', 'Disco', caminho) end
  opcao('Anel', 'Shape', shape)
  local s2, s3 = AN:arcos(f, cor .. ',61', cor .. ',255', zoom and 8 or nil)
  opcao('Anel', 'Shape2', s2)
  opcao('Anel', 'Shape3', s3)
  opcao('Anel', 'Shape4', AN:ponto(cor .. ',255', ponto))
end

-- posição dos dígitos (centro de cada um, relativo à máscara) e da unidade
local function layoutDig(chars, uni)
  local n = #chars
  local uw = (uni ~= '' and (L.uniW or 0) + L.uniGap) or 0
  local esq = L.c - (n * L.dig + uw) / 2
  local xs = {}
  for k = 1, n do xs[k] = esq + (n - k + 0.5) * L.dig end
  return xs, esq + n * L.dig + L.uniGap
end
local function porDireita(chars, k) return chars[#chars - k + 1] end

local function digitosRepouso()
  local chars = caracteres(VIS.texto)
  local xs, ux = layoutDig(chars, VIS.uni)
  for k = 1, 3 do
    opcao('DS' .. k, 'Text', '')
    opcao('DE' .. k, 'Text', porDireita(chars, k) or '')
    opcao('DE' .. k, 'X', num(xs[k] or 0))
    opcao('DE' .. k, 'Y', num(L.digY))
  end
  opcao('Uni', 'Text', VIS.uni)
  opcao('Uni', 'X', num(L.anelX + ux))
end

local function digitosMontar(de, para, uni, dir)
  local a, b = caracteres(de), caracteres(para)
  local xa = layoutDig(a, VIS.uni)
  local xb, ux = layoutDig(b, uni)
  local rola = {}
  local mesmoTam = (#a == #b) and (uni == VIS.uni)
  for k = 1, 3 do
    local ca, cb = porDireita(a, k) or '', porDireita(b, k) or ''
    if ca ~= cb or not mesmoTam then
      opcao('DS' .. k, 'Text', ca)
      opcao('DS' .. k, 'X', num(xa[k] or 0))
      opcao('DE' .. k, 'Text', cb)
      opcao('DE' .. k, 'X', num(xb[k] or 0))
      rola[#rola + 1] = k
    else
      opcao('DS' .. k, 'Text', '')
      opcao('DE' .. k, 'Text', cb)
      opcao('DE' .. k, 'X', num(xb[k] or 0))
      opcao('DE' .. k, 'Y', num(L.digY))
    end
  end
  opcao('Uni', 'Text', uni)
  opcao('Uni', 'X', num(L.anelX + ux))
  return {ks = rola, dir = dir}
end

local function digitosQuadro(R, e)
  for _, k in ipairs(R.ks) do
    opcao('DS' .. k, 'Y', num(L.digY - R.dir * L.passo * e))
    opcao('DE' .. k, 'Y', num(L.digY + R.dir * L.passo * (1 - e)))
  end
end

-- número a 62 % quando o dado é velho (como o protótipo); a unidade já é 70 %
local function corNumero(apagado)
  local a = apagado and 0.62 or 1
  local cDig = string.format('%s,%d', T.on, math.floor(255 * a + 0.5))
  local cUni = string.format('%s,%d', T.on, math.floor(179 * a + 0.5))
  for k = 1, 3 do opcao('DS' .. k, 'FontColor', cDig); opcao('DE' .. k, 'FontColor', cDig) end
  opcao('Uni', 'FontColor', cUni)
end

local function avaliarAnel(A, s)
  local v = {}
  v.f = A.f0 + (A.f1 - A.f0) * anim.valor(molaDado, s)
  v.cor = A.c0 == A.c1 and A.c1 or anim.cor(A.c0, A.c1, anim.saida(s / DUR_COR)):gsub(',%d+$', '')
  v.amp = A.a0 + (A.a1 - A.a0) * anim.valor(molaBoing, s)
  v.rot = A.r0 + (A.r1 - A.r0) * anim.valor(molaEsp, s)
  v.ponto = A.p0 + (A.p1 - A.p0) * anim.valor(molaBoing, s)
  v.dig = anim.valor(molaRola, s)
  return v
end

local function aplicarAnel(v, zoom)
  desenharAnel(v.f, v.cor, v.amp, v.rot, v.ponto, zoom)
end

local function fimAnel()
  local A = AR
  AR = nil
  VIS.f, VIS.cor, VIS.amp, VIS.rot, VIS.ponto = A.f1, A.c1, A.a1, A.r1, A.p1
  desenharAnel(A.f1, A.c1, A.a1, A.r1, A.p1, A.zoom)
  digitosRepouso()
end

-- ---------------------------------------------------------------- timer

local function ligarTimer()
  if S.timer then return end
  S.timer = true
  S.ligouEm = os.clock()
  bang('!CommandMeasure', 'mAT', 'Execute 1')
end

local function pararTimerSeOcioso()
  if AR == nil and AB == nil and S.timer then
    S.timer = false
    bang('!CommandMeasure', 'mAT', 'Stop 1')
  end
end

-- Leva o anel ao estado E. varrer = o arco sai do 0 (entrada; travessia da escala ampliada).
local function mostrarAnel(E, varrer, atraso)
  local forma1 = E.forma
  local rot1 = VIS.rot
  if VIS.forma ~= forma1 and not varrer then rot1 = VIS.rot + (forma1 > VIS.forma and ROT or -ROT) end
  local p1 = E.zoom and 1 or 0
  local uni1 = (E.texto == '–') and '' or '%'
  local dir = 1
  local vNovo, vVelho = tonumber(E.texto), tonumber(VIS.texto)
  if vNovo and vVelho and vNovo < vVelho then dir = -1 end
  corNumero(E.apagado)
  opcao('Cap', 'Text', E.cap or '')

  if not animando() then
    AR = nil
    VIS.texto, VIS.uni = E.texto, uni1
    VIS.f, VIS.cor, VIS.amp, VIS.rot, VIS.ponto, VIS.forma, VIS.zoom = E.f, E.cor, AMP[forma1], rot1, p1, forma1, E.zoom
    desenharAnel(E.f, E.cor, AMP[forma1], rot1, p1, E.zoom)
    digitosRepouso()
    pararTimerSeOcioso()
    return
  end

  -- interrompe o que estava em curso a partir do ponto atual
  if AR then
    local v = avaliarAnel(AR, os.clock() - AR.t0)
    VIS.f, VIS.cor, VIS.amp, VIS.rot, VIS.ponto = v.f, v.cor, v.amp, v.rot, v.ponto
    AR = nil
    digitosRepouso()
  end

  local cruza = (VIS.zoom ~= E.zoom)
  local A = {
    t0 = os.clock() + (atraso or 0),
    f0 = (varrer or cruza) and 0 or VIS.f, f1 = E.f,
    c0 = VIS.cor or E.cor, c1 = E.cor,
    a0 = VIS.amp, a1 = AMP[forma1],
    r0 = VIS.rot, r1 = rot1,
    p0 = VIS.ponto, p1 = p1,
    zoom = E.zoom,
  }
  if VIS.texto ~= E.texto or VIS.uni ~= uni1 then A.rola = digitosMontar(VIS.texto, E.texto, uni1, dir) end
  VIS.texto, VIS.uni, VIS.forma, VIS.zoom = E.texto, uni1, forma1, E.zoom
  A.dur = math.max(math.abs(A.f1 - A.f0) > 0.0005 and molaDado.dur or 0, A.c0 ~= A.c1 and DUR_COR or 0,
    A.a0 ~= A.a1 and molaBoing.dur or 0, A.r0 ~= A.r1 and molaEsp.dur or 0,
    A.p0 ~= A.p1 and molaBoing.dur or 0, A.rola and molaRola.dur or 0)
  if A.dur <= 0 then
    VIS.f, VIS.cor, VIS.amp, VIS.rot, VIS.ponto = A.f1, A.c1, A.a1, A.r1, A.p1
    desenharAnel(A.f1, A.c1, A.a1, A.r1, A.p1, A.zoom)
    digitosRepouso()
    return
  end
  AR = A
  local v = avaliarAnel(A, 0)
  aplicarAnel(v, A.zoom)
  if A.rola then digitosQuadro(A.rola, v.dig) end
  ligarTimer()
end

-- ---------------------------------------------------------------- coluna da direita

local function medirW(m)
  bang('!UpdateMeter', m)
  local mm = SKIN:GetMeter(m)
  return mm and mm:GetW() or 0
end

-- altura de uma lista de itens
local function alturaPainel(P)
  local h, prev = 0, nil
  for _, it in ipairs(P) do
    if it.tipo == 'nome' then
      if prev then h = h + L.vaoConta end
      h = h + L.nomeH
    else
      h = h + (prev == 'nome' and L.vaoLinha or L.vaoLinha) + L.linhaH
    end
    prev = it.tipo
  end
  return h
end

-- desenha a barra j com fração f e alfa a (0..1)
local function barraShape(j, f, cor, a)
  local bw = L.barW[j] or 0
  local w = math.max(2 * sc, bw * limitar(f, 0, 1))
  local ta = math.floor(255 * a + 0.5)
  opcao('Rb' .. j, 'Shape', string.format('Rectangle 0,0,%s,%s,%s | Fill Color %s,%d | StrokeWidth 0',
    num(bw), num(L.barH), num(L.barH / 2), T.trilho, ta))
  opcao('Rb' .. j, 'Shape2', string.format('Rectangle 0,0,%s,%s,%s | Fill Color %s,%d | StrokeWidth 0',
    num(w), num(L.barH), num(L.barH / 2), cor, ta))
end

local function coresPainel(a)
  local A = function(c, base) return string.format('%s,%d', c, math.floor((base or 255) * a + 0.5)) end
  for i = 1, MAX_NOMES do
    opcao('Nm' .. i, 'FontColor', A(T.on))
    opcao('Tg' .. i, 'FontColor', A(T.onV))
  end
  for j = 1, MAX_LINHAS do
    opcao('Rl' .. j, 'FontColor', A(T.onV))
    opcao('Rv' .. j, 'FontColor', A(T.on))
  end
end

-- Escreve os itens do painel nas posições; devolve a tabela de linhas (para animar as barras).
local function montarPainel(P, topo)
  local y, prev = topo, nil
  local ni, lj = 0, 0
  local linhas = {}
  -- coluna do rótulo: 22 px (5h/7d) ou mais larga se houver rótulo longo (Fable)
  local lw = L.rotW
  for _, it in ipairs(P) do
    if it.tipo == 'linha' and #caracteres(it.rot) > 3 then lw = L.rotWLargo end
  end
  local bw = L.ladoW - lw - L.valW - 2 * L.gapLinha
  for _, it in ipairs(P) do
    if it.tipo == 'nome' then
      if ni >= MAX_NOMES then break end
      if prev then y = y + L.vaoConta end
      ni = ni + 1
      local nm, tg = 'Nm' .. ni, 'Tg' .. ni
      mostrarMeter(nm, true)
      opcao(nm, 'Text', comum.textoSeguro(it.nome))
      opcao(nm, 'Y', num(y + L.nomeDY))
      local w = medirW(nm)
      mostrarMeter(tg, true)
      opcao(tg, 'Text', comum.textoSeguro(it.tag or ''))
      opcao(tg, 'X', num(L.ladoX + w + L.tagGap))
      opcao(tg, 'W', num(math.max(0, L.ladoX + L.ladoW - (L.ladoX + w + L.tagGap))))
      opcao(tg, 'Y', num(y + L.tagDY))
      y = y + L.nomeH
    else
      if lj >= MAX_LINHAS then break end
      lj = lj + 1
      y = y + L.vaoLinha
      local rl, rb, rv = 'Rl' .. lj, 'Rb' .. lj, 'Rv' .. lj
      mostrarMeter(rl, true)
      opcao(rl, 'Text', comum.textoSeguro(it.rot))
      opcao(rl, 'Y', num(y + L.rotDY))
      if it.tipo == 'aviso' then
        opcao(rl, 'W', num(L.ladoW))
        mostrarMeter(rb, false)
        mostrarMeter(rv, false)
        linhas[lj] = {chave = it.chave}
      else
        opcao(rl, 'W', num(lw))
        L.barW[lj] = bw
        mostrarMeter(rb, true)
        opcao(rb, 'X', num(L.ladoX + lw + L.gapLinha))
        opcao(rb, 'Y', num(y + L.barDY))
        mostrarMeter(rv, true)
        opcao(rv, 'Text', it.txt)
        opcao(rv, 'Y', num(y + L.rotDY))
        linhas[lj] = {chave = it.chave, f = it.f, cor = it.cor}
      end
      y = y + L.linhaH
    end
    prev = it.tipo
  end
  for i = ni + 1, MAX_NOMES do mostrarMeter('Nm' .. i, false); mostrarMeter('Tg' .. i, false) end
  for j = lj + 1, MAX_LINHAS do
    mostrarMeter('Rl' .. j, false); mostrarMeter('Rb' .. j, false); mostrarMeter('Rv' .. j, false)
  end
  return linhas
end

local function avaliarBarras(B, s)
  local e = anim.valor(molaDado, s)
  local a = B.fade and anim.saida(s / DUR_FADE) or 1
  return e, a
end

local function quadroBarras(B, s)
  local e, a = avaliarBarras(B, s)
  for j, l in pairs(B.linhas) do
    if l.f then
      local f0 = l.f0 or l.f
      barraShape(j, f0 + (l.f - f0) * e, l.cor, a)
    end
  end
  if B.fade then coresPainel(a) end
end

local function fimBarras()
  local B = AB
  AB = nil
  for j, l in pairs(B.linhas) do if l.f then barraShape(j, l.f, l.cor, 1) end end
  coresPainel(1)
end

-- Mostra o painel P. fade: entra com alfa (troca do hover); senão cada barra anda do valor anterior
-- (mesma chave) ou, na entrada, do zero.
local function mostrarPainel(P, topo, modo)
  local antigas = {}
  for _, l in pairs(PAINEL) do if l.chave then antigas[l.chave] = l end end
  if AB then
    -- interrompe: o que estava em curso fica no ponto atual
    local e = anim.valor(molaDado, os.clock() - AB.t0)
    for _, l in pairs(AB.linhas) do
      if l.f and antigas[l.chave] then antigas[l.chave].f = (l.f0 or l.f) + (l.f - (l.f0 or l.f)) * e end
    end
    AB = nil
  end
  local linhas = montarPainel(P, topo)
  local mexe = false
  for _, l in pairs(linhas) do
    if l.f then
      if modo == 'entrada' then
        l.f0 = 0
      elseif modo ~= 'fade' and antigas[l.chave] and antigas[l.chave].f then
        l.f0 = antigas[l.chave].f
      end
      if l.f0 and math.abs(l.f0 - l.f) > 0.0005 then mexe = true end
    end
  end
  PAINEL = linhas
  local fade = (modo == 'fade')
  if not animando() or (not mexe and not fade) then
    for j, l in pairs(linhas) do if l.f then barraShape(j, l.f, l.cor, 1) end end
    coresPainel(1)
    pararTimerSeOcioso()
    return
  end
  AB = {t0 = os.clock(), linhas = linhas, fade = fade,
    dur = math.max(mexe and molaDado.dur or 0, fade and DUR_FADE or 0)}
  quadroBarras(AB, 0)
  ligarTimer()
end

-- ---------------------------------------------------------------- legenda, bloco e altura

local function aplicarLayout(E)
  local hN, hA = alturaPainel(E.painelNormal), alturaPainel(E.painelAtiva)
  local corpo = math.max(L.anel, hN, hA)
  local anelY = L.corpoY + (corpo - L.anel) / 2
  opcao('Anel', 'Y', num(anelY))
  opcao('Hit', 'Y', num(anelY))
  opcao('Masc', 'Y', num(anelY + L.mascDY))
  opcao('Uni', 'Y', num(anelY + L.uniDY))
  opcao('Cap', 'Y', num(anelY + L.capDY))
  local legY = L.corpoY + corpo + L.legGap
  local h
  if E.bloco then
    mostrarMeter('Leg', false)
    mostrarMeter('Bloco', true)
    mostrarMeter('BlocoTxt', true)
    opcao('BlocoTxt', 'Text', E.bloco)
    opcao('BlocoTxt', 'Y', num(legY + L.blocoPad))
    bang('!UpdateMeter', 'BlocoTxt')
    local th = SKIN:GetMeter('BlocoTxt'):GetH()
    h = th + 2 * L.blocoPad
    opcao('Bloco', 'Y', num(legY))
    opcao('Bloco', 'Shape', string.format('Rectangle 0,0,%s,%s,%s | Fill Color %s,72 | StrokeWidth 0',
      num(L.ladoX + L.ladoW - L.pad), num(h), num(14 * sc), T.velho))
  else
    mostrarMeter('Bloco', false)
    mostrarMeter('BlocoTxt', false)
    mostrarMeter('Leg', true)
    local pre = E.prefixo or ''
    local txt = (pre ~= '' and (pre .. ', ') or '') .. (E.resto or '')
    opcao('Leg', 'Text', comum.textoSeguro(txt))
    local n = #caracteres(pre)
    opcao('Leg', 'InlinePattern', '^.{' .. n .. '}')
    opcao('Leg', 'InlinePattern2', '^.{' .. n .. '}')
    opcao('Leg', 'Y', num(legY))
    bang('!UpdateMeter', 'Leg')
    h = SKIN:GetMeter('Leg'):GetH()
  end
  local H = legY + h + L.pad
  opcao('Cartao', 'Shape', string.format('Rectangle 0,0,%s,%s,%s | Fill Color %s | StrokeWidth 0',
    num(L.w), num(H), num(L.raio), T.s))
  local topoN = L.corpoY + (corpo - hN) / 2
  local topoA = L.corpoY + (corpo - hA) / 2
  return topoN, topoA
end

-- ---------------------------------------------------------------- ciclo

local function painelAtual(E)
  if S.hover then return E.painelAtiva, S.topoA end
  return E.painelNormal, S.topoN
end

local function assinaturaPainel(P)
  local t = {}
  for _, it in ipairs(P) do
    t[#t + 1] = table.concat({it.tipo, it.nome or '', it.tag or '', it.rot or '', it.txt or '',
      it.cor or '', it.f and string.format('%.4f', it.f) or ''}, '\1')
  end
  return table.concat(t, '\2')
end

-- Recalcula e mostra só o que mudou. modo: nil (troca), 'entrada'.
local function aplicar(modo)
  local agora = os.time()
  local E = derivar(S.snap, agora)
  S.E = E
  local mexeu = false

  local sigL = table.concat({E.bloco or '', E.prefixo or '', E.resto or '',
    alturaPainel(E.painelNormal), alturaPainel(E.painelAtiva)}, '\1')
  if sigL ~= SIG.layout or modo == 'entrada' then
    SIG.layout = sigL
    S.topoN, S.topoA = aplicarLayout(E)
    mexeu = true
  end

  local sigA = table.concat({E.texto, string.format('%.4f', E.f), E.cor, E.forma, tostring(E.zoom),
    E.cap or '', tostring(E.apagado)}, '\1')
  if sigA ~= SIG.anel or modo == 'entrada' then
    SIG.anel = sigA
    if modo == 'entrada' then
      AR = nil
      VIS.texto, VIS.uni, VIS.f, VIS.amp, VIS.rot, VIS.ponto, VIS.forma, VIS.zoom = '', '', 0, 0, 0, 0, E.forma, E.zoom
      VIS.cor = E.cor
      digitosRepouso()
      desenharAnel(0, E.cor, 0, 0, 0, false)
      mostrarAnel(E, true, 0)
    else
      mostrarAnel(E, false)
    end
    mexeu = true
  end

  local P, topo = painelAtual(E)
  local sigP = assinaturaPainel(P) .. '\3' .. num(topo) .. tostring(S.hover)
  if sigP ~= SIG.painel or modo == 'entrada' then
    local troca = SIG.painelHover ~= nil and SIG.painelHover ~= S.hover
    SIG.painel = sigP
    SIG.painelHover = S.hover
    mostrarPainel(P, topo, modo == 'entrada' and 'entrada' or (troca and 'fade' or nil))
    mexeu = true
  end

  if mexeu then
    bang('!UpdateMeter', '*')
    bang('!Redraw')
    comum.log('info', string.format('aplicar %s: %s %s%% faixa %d zoom %s parado %s', modo or 'troca',
      E.nome and 'conta' or '-', E.texto, E.forma, tostring(E.zoom), tostring(E.parado)))
  end
end

local function lerSnap(forcar)
  S.leitorSnap.caminho = comum.caminhoSnapshot()
  local d, mudou = S.leitorSnap:ler(forcar)
  if d then S.snap = d end
  return mudou
end

local function lerAgenda(forcar)
  S.leitor.caminho = comum.caminhoAgenda()
  local d, mudou = S.leitor:ler(forcar)
  if not d or not mudou then return end
  S.animSistema = not (type(d.ambiente) == 'table' and d.ambiente.animacoes == false)
end

local function seguro(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    if comum then comum.log('erro', err) else print('Horizonte Claude: ' .. tostring(err)) end
  end
end

function Initialize()
  seguro(function()
    local carregar = dofile(SKIN:GetVariable('@') .. 'Lua\\carregar.lua')
    comum = carregar('comum')
    anim = carregar('anim')
    anelMod = carregar('anel')
    comum.iniciar('Claude')
    molaDado = anim.nomeada('dado', 0.01)     -- crítica: o arco e as barras nunca passam do valor
    molaRola = anim.nomeada('rolagem')        -- dígitos, igual ao Relógio
    molaBoing = anim.nomeada('boing', 0.01)   -- forma do disco e ponto do zoom: quicam
    molaEsp = anim.nomeada('espacial', 0.01)  -- giro do disco na troca de faixa

    sc = tonumber(var('Scale', '1')) or 1
    AN = anelMod.novo(136, 9, sc)
    L.w, L.pad, L.raio = 330 * sc, 24 * sc, (tonumber(var('RaioCartao', '32')) or 32) * sc
    L.anel, L.anelX, L.corpoY = 136 * sc, 24 * sc, 59 * sc
    L.c = 68 * sc                -- centro do anel, relativo à máscara (mesmo X do anel)
    L.dig = 21.8 * sc            -- avanço de um dígito a 40 px (letter-spacing -0,03 em)
    L.uniGap = 1 * sc
    L.digY = -4.8 * sc           -- Y do dígito dentro da máscara
    L.passo = 44 * sc            -- 1,1 em
    L.mascDY, L.uniDY, L.capDY = 46 * sc, 66 * sc, 90 * sc
    L.ladoX, L.ladoW = 180 * sc, 126 * sc
    L.nomeH, L.nomeDY, L.tagDY, L.tagGap = 21 * sc, 0, 3 * sc, 4 * sc
    L.linhaH, L.vaoLinha, L.vaoConta = 17.5 * sc, 10 * sc, 14 * sc
    L.rotW, L.rotWLargo, L.valW, L.gapLinha = 22 * sc, 36 * sc, 34 * sc, 8 * sc
    L.rotDY, L.barDY, L.barH = 0, 6.75 * sc, 4 * sc
    L.barW = {}
    L.legGap, L.blocoPad = 16 * sc, 10 * sc

    T.ok = var('ClaudeOk', '48,164,108')
    T.alerta = var('ClaudeAlerta', '245,166,35')
    T.critico = var('ClaudeCritico', '229,72,77')
    T.velho = var('ClaudeVelho', '116,118,132')
    T.trilho = var('ClaudeTrilho', '70,70,78')
    T.s = var('CorS', '21,48,45')
    T.on = var('CorOn', '226,241,236')
    T.onV = var('CorOnV', '166,191,185')

    S.animVar = var('Animacoes', '1') ~= '0'
    S.releitura = tonumber(var('ReleituraS', '60')) or 60
    S.releituraSnap = tonumber(var('ReleituraClaudeS', '20')) or 20
    S.paradoS = tonumber(var('TrayParadoS', '150')) or 150
    S.debugTray = var('DebugTray', '')

    -- largura do '%' medida no próprio meter
    bang('!SetOption', 'Uni', 'Text', '%')
    bang('!UpdateMeter', 'Uni')
    L.uniW = SKIN:GetMeter('Uni'):GetW()
    bang('!SetOption', 'Uni', 'Text', '')

    S.leitor = comum.leitor(comum.caminhoAgenda(), {schemaVersion = 1})
    S.leitorSnap = comum.leitor(comum.caminhoSnapshot())
    lerAgenda(true)
    lerSnap(true)
    S.minuto = os.date('%H:%M')
    aplicar('entrada')
  end)
end

function Update()
  if not comum then return '' end
  seguro(function()
    local agora = os.clock()
    -- vigia: algo animando e nenhum passo há mais de 0,5 s = a lista do ActionTimer acabou sozinha
    if (AR or AB) and S.timer and agora - math.max(S.ultPasso or 0, S.ligouEm or 0) > 0.5 then
      comum.log('erro', 'ActionTimer parado com animação em curso: religando')
      S.timer = false
      ligarTimer()
    end
    S.seg, S.segSnap = S.seg + 1, S.segSnap + 1
    local recalc = false
    if S.segSnap >= S.releituraSnap then
      S.segSnap = 0
      lerSnap(false)
      recalc = true        -- mesmo sem mudança no arquivo: a bandeja pode ter parado
    end
    local m = os.date('%H:%M')
    if m ~= S.minuto then S.minuto = m; recalc = true end
    if S.seg >= S.releitura then S.seg = 0; lerAgenda(false) end
    if recalc then aplicar() end
  end)
  return ''
end

function Passo()
  seguro(function()
    S.passos = (S.passos or 0) + 1
    S.ultPasso = os.clock()
    if not AR and not AB then
      S.ociosos = (S.ociosos or 0) + 1
      pararTimerSeOcioso()
      if S.timer then S.timer = false; bang('!CommandMeasure', 'mAT', 'Stop 1') end
      return
    end
    local agora = os.clock()
    local ga, gp = false, false
    if AR then
      local s = agora - AR.t0
      if s >= AR.dur then
        fimAnel(); ga = true
      elseif s >= 0 then
        local v = avaliarAnel(AR, s)
        aplicarAnel(v, AR.zoom)
        if AR.rola then digitosQuadro(AR.rola, v.dig) end
        ga = true
      end
    end
    if AB then
      local s = agora - AB.t0
      if s >= AB.dur then fimBarras() else quadroBarras(AB, s) end
      gp = true
    end
    if ga then bang('!UpdateMeterGroup', 'GA') end
    if gp then bang('!UpdateMeterGroup', 'GP') end
    if ga or gp then bang('!Redraw') end
    pararTimerSeOcioso()
  end)
end

-- Hover no anel: a coluna da direita troca para todas as barras da conta ativa.
function Hover(v)
  seguro(function()
    local h = tostring(v) == '1'
    if h == S.hover then return end
    S.hover = h
    if S.E then aplicar() end
  end)
end

-- Relê o snapshot (e o agenda.json) na hora. O agenda_sync chama depois de gravar.
function Recarregar()
  seguro(function()
    lerAgenda(true)
    lerSnap(true)
    S.debugTray = var('DebugTray', S.debugTray)
    aplicar()
  end)
end

function Entrada()
  seguro(function() aplicar('entrada') end)
end

-- Clique no bloco "bandeja parada" (e menu de contexto): abre o executável da bandeja.
function AbrirBandeja()
  seguro(function()
    local exe = comum.expandirAmbiente(var('TrayExe', ''))
    if exe == '' or not comum.existe(exe) then
      comum.log('erro', 'TrayExe não encontrado (ajuste no Local.inc)')
      return
    end
    if exe:find('[%[%]"#]') then
      comum.log('erro', 'TrayExe com caractere que o Rainmeter leria como bang ou variável')
      return
    end
    -- a bandeja já tem trava de instância única; mesmo assim, nada de lançar outra com ela viva
    if trayVivo() then
      comum.log('info', 'AbrirBandeja: a bandeja já está rodando')
      return
    end
    bang('["' .. exe .. '"]')
    comum.log('info', 'bandeja aberta pelo widget')
    S.segSnap = S.releituraSnap - 5   -- relê em ~5 s
  end)
end

-- Depuração: ForcarTray('0') finge a bandeja fechada, ('1') aberta, ('') volta ao real.
function ForcarTray(v)
  seguro(function()
    S.debugTray = tostring(v or '')
    aplicar()
  end)
end

-- Depuração: esquece o último estado bom e relê (prova "sem snapshot desde o início").
function Esquecer()
  seguro(function()
    S.snap = nil
    S.leitorSnap = comum.leitor(comum.caminhoSnapshot())
    lerSnap(true)
    aplicar()
  end)
end

function Log(v)
  if comum then comum.debug = tostring(v) == '1' end
end

function Contar()
  if not comum then return end
  local d = comum.debug
  comum.debug = true
  comum.log('info', string.format('passos %d, ociosos %d, anel %s, barras %s, timer %s',
    S.passos or 0, S.ociosos or 0, tostring(AR ~= nil), tostring(AB ~= nil), tostring(S.timer)))
  comum.debug = d
  S.passos, S.ociosos = 0, 0
end
