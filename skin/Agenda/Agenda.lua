-- Horizonte\Agenda: próximos 14 dias agrupados por dia, vãos livres de hoje, séries diárias
-- colapsadas, saúde de cada fonte e modo privado (docs/widgets.md § Agenda).
-- Arquivo em UTF-16 LE com BOM (assim os acentos chegam certos aos meters).
-- Measure "mLeitor": o agenda_sync chama Recarregar() depois de gravar o agenda.json.
-- Depuração: DebugHora=HH:MM, Forcar('HH:MM'), DebugAgenda=<json>, Entrada(), Esquecer().
--
-- Regra de título real: este script nunca grava título de evento em log.

local comum, anim
local mRow, mBoing
local CFG = {}
local NSLOT = 26
local W = 380
local NDOT = 4

local S = {
  pronto = false,
  forcada = nil,       -- segundos desde a meia-noite (depuração)
  minuto = nil,
  seg = 0,
  dados = nil,
  privado = false,
  animVar = true, animSistema = true,
  timer = false,       -- ActionTimer rodando
  sobre = 0,           -- slot com o mouse em cima
  tPasso = nil,
}

-- SLOT[i] = {c = conteúdo aplicado (ou nil), a = alfa 0..1, dy = deslocamento, hv = hover 0..1}
-- SLOT[0] = faixa de erro
local SLOT = {}
local E = nil          -- conteúdo atual (montar)
local V = nil          -- visual do cabeçalho/cartão: {h, lockR, lockP, headA, dots = {{cor, r}}}
local A = nil          -- transição em curso

-- tempos (s)
local T_SAI = 0.11     -- linha antiga some
local T_ENTRA = 0.22   -- linha nova aparece (4 px de baixo)
local T_COR = 0.30     -- cor dos pontos e do cadeado
local T_HOVER = 0.12

-- geometria vertical (px lógicos, medidas do protótipo)
local Y_LISTA = 68
local ALT = {g = 36.2, ev = 38, gap = 30.9, nada = 30.9, mais = 30.9}
local CENTRO = {g = 23.1, ev = 19, gap = 15.45, nada = 15.45, mais = 21.45}
local PAD_FIM = 18

local COR_FONTE = {pessoal = 'CorAgPes', corporativo = 'CorAgCor', feriados = 'CorAgFer'}
local NOME_FONTE = {pessoal = 'Agenda pessoal', corporativo = 'Agenda corporativa', feriados = 'Feriados'}

local function bang(...) SKIN:Bang(...) end
local num = function(x) return string.format('%.2f', x) end
local function var(nome, padrao)
  local v = SKIN:GetVariable(nome, padrao)
  if v == nil or v == '' then return padrao end
  return v
end
local function animando() return S.animVar and S.animSistema end
local function sc(x) return x * CFG.scale end
local function cor(tok) return CFG.cor[tok] end

-- ---------------------------------------------------------------- tempo
local function agora()
  if S.forcada then return comum.inicioDoDia(os.time()) + S.forcada end
  return os.time()
end
local function hhmmParaSeg(s)
  local h, m = tostring(s or ''):match('^(%d%d?):(%d%d)$')
  if not h then return nil end
  return tonumber(h) * 3600 + tonumber(m) * 60
end
local function difDias(a, b) return math.floor((a - b) / 86400 + 0.5) end

-- "Hoje", "amanhã, sábado", "segunda, 5/10"
local function rotuloDia(dia, dia0)
  local d = os.date('*t', dia + 43200)
  local n = difDias(dia, dia0)
  if n == 0 then return 'Hoje' end
  if n == 1 then return 'amanhã, ' .. comum.DIAS[d.wday] end
  return comum.DIAS[d.wday] .. ', ' .. d.day .. '/' .. d.month
end

-- ---------------------------------------------------------------- fontes: cor e saúde
local function corFonte(id, hex)
  local tok = COR_FONTE[id]
  if tok then return cor(tok) end
  return comum.corHex(hex) or cor('CorOnV')
end

-- 'ok' | 'alerta' (offline, 5xx, desconhecido: dado velho) | 'critico' (precisa de ação)
local function classe(status)
  if status == 'ok' then return 'ok' end
  if status == 'formato' or status == 'sem_credencial' then return 'critico' end
  local c = tostring(status or ''):match('^http(%d)%d%d$')
  if c == '4' then return 'critico' end
  return 'alerta'
end

local function rotuloStatus(st)
  if st == 'offline' then return 'offline' end
  if st == 'formato' then return 'com feed inválido' end
  if st == 'sem_credencial' then return 'sem credencial' end
  local cod = tostring(st or ''):match('^http(%d+)$')
  if cod then return 'com erro ' .. cod end
  return tostring(st)
end

local function maiuscula(s)
  s = tostring(s or '')
  return s:sub(1, 1):upper() .. s:sub(2)
end

-- pontos de saúde (até NDOT) + linhas da faixa de erro
local function saude(ag)
  local dots, linhas, pior = {}, {}, nil
  local L = S.leitor
  if not S.dados then
    if L.erro == 'sem arquivo' or not L.erro then
      linhas[1] = 'Agenda indisponível. O agenda-sync ainda não gravou o agenda.json; rode agenda-sync sync'
    elseif L.erro:match('^schemaVersion') then
      linhas[1] = 'Agenda indisponível. O agenda.json é de outra versão; atualize o Horizonte'
    else
      linhas[1] = 'Agenda indisponível. O agenda.json está ilegível; rode agenda-sync sync'
    end
    pior = 'critico'
  elseif L.erro == 'sem arquivo' then
    linhas[1] = 'Arquivo da agenda sumiu. Mostrando a última leitura; rode agenda-sync sync'
    pior = 'alerta'
  elseif L.erro and L.erro:match('^schemaVersion') then
    linhas[1] = 'Arquivo da agenda de outra versão. Mostrando a última leitura; atualize o Horizonte'
    pior = 'critico'
  elseif L.erro then
    linhas[1] = 'Arquivo da agenda ilegível. Mostrando a última leitura'
    pior = 'alerta'
  end
  local fontes = S.dados and type(S.dados.sources) == 'table' and S.dados.sources or {}
  local hoje0 = comum.inicioDoDia(ag)
  for _, f in ipairs(fontes) do
    if type(f) == 'table' and #dots < NDOT then
      local cl = classe(f.status)
      local id = tostring(f.id or f.nome or '?')
      local d = {cl = cl}
      if cl == 'ok' then
        d.cor = corFonte(f.id, f.cor)
        d.tip = id .. ': sincronizada'
      else
        d.cor = cl == 'critico' and cor('CorCritico') or cor('CorAlerta')
        d.tip = id .. ': ' .. tostring(f.erro or rotuloStatus(f.status))
        local frase = (NOME_FONTE[f.id] or maiuscula(f.nome or id)) .. ' ' .. rotuloStatus(f.status)
        local ok = tonumber(f.lastOkAt)
        if ok and f.status ~= 'sem_credencial' then
          frase = frase .. ', dados de ' .. (ok >= hoje0 and comum.hhmm(ok) or os.date('%d/%m', ok))
        end
        local det = f.erro and (' ' .. maiuscula(f.erro)) or ''
        linhas[#linhas + 1] = frase .. '.' .. det
        if cl == 'critico' or not pior then pior = cl end
      end
      dots[#dots + 1] = d
    end
  end
  return dots, linhas, pior
end

-- ---------------------------------------------------------------- lista (o que a Agenda diz)
local function ocultas()
  local t = {}
  for id in tostring(CFG.ocultas or ''):gmatch('[^,%s]+') do t[id] = true end
  return t
end

-- eventos visíveis no instante ag: não encerrados, até o fim do horizonte, sem fonte oculta
local function elegiveis(ag)
  local dia0 = comum.inicioDoDia(ag)
  local fimH = comum.inicioDoDia(ag, CFG.dias + 1)
  local oc = ocultas()
  local out = {}
  local evs = S.dados and type(S.dados.events) == 'table' and S.dados.events or {}
  for idx, e in ipairs(evs) do
    if type(e) == 'table' and not oc[e.source] then
      if e.allDay then
        local s, f = comum.epochDeData(e.startDate), comum.epochDeData(e.endDate)
        if s then
          local s0 = comum.inicioDoDia(s)
          local f0 = f and comum.inicioDoDia(f) or s0 + 86400
          if f0 > dia0 and s0 < fimH then
            local dia = math.max(s0, dia0)
            out[#out + 1] = {e = e, dia = dia, ini = dia, fim = f0, allDay = true, idx = idx}
          end
        end
      else
        local s, f = tonumber(e.start), tonumber(e['end'])
        if s and f and f > ag and s < fimH then
          local dia = comum.inicioDoDia(math.max(s, dia0))
          out[#out + 1] = {e = e, dia = dia, ini = s, fim = f, idx = idx}
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.dia ~= b.dia then return a.dia < b.dia end
    if (a.allDay or false) ~= (b.allDay or false) then return a.allDay == true end
    if a.ini ~= b.ini then return a.ini < b.ini end
    return a.idx < b.idx
  end)
  return out, dia0, fimH
end

-- Série recorrente diária: agrupa as ocorrências JÁ EXPANDIDAS pelo helper (mesma fonte, título,
-- hora de início e duração, recurring=true). Colapsa com ≥3 ocorrências e no máximo 3 dias entre
-- uma e outra (sex → seg). Rótulo "diário" (todo dia) ou "seg a sex" (todos os dias úteis).
-- Não é expansão de recorrência (essa é só do helper): é agrupamento para exibir.
local function colapsar(itens, dia0)
  local grupos, ordem = {}, {}
  for _, it in ipairs(itens) do
    local e = it.e
    if not it.allDay and e.recurring == true then
      local k = tostring(e.source) .. '|' .. tostring(e.title) .. '|' .. os.date('%H:%M', it.ini) .. '|' .. (it.fim - it.ini)
      if not grupos[k] then grupos[k] = {}; ordem[#ordem + 1] = k end
      table.insert(grupos[k], it)
    end
  end
  for _, k in ipairs(ordem) do
    local g = grupos[k]
    if #g >= 3 then
      local dias, maxGap, uteis = {}, 0, true
      for i, it in ipairs(g) do
        dias[i] = difDias(comum.inicioDoDia(it.ini), dia0)
        local wd = os.date('*t', it.ini).wday
        if wd == 1 or wd == 7 then uteis = false end
        if i > 1 then maxGap = math.max(maxGap, dias[i] - dias[i - 1]) end
      end
      if maxGap <= 3 and maxGap >= 1 then
        local rot = nil
        local span = dias[#dias] - dias[1] + 1
        if maxGap == 1 and #g == span then
          rot = 'diário'
        elseif uteis then
          local n = 0
          for d = dias[1], dias[#dias] do
            local wd = os.date('*t', dia0 + d * 86400 + 43200).wday
            if wd ~= 1 and wd ~= 7 then n = n + 1 end
          end
          if n == #g then rot = 'seg a sex' end
        end
        g[1].serie, g[1].rot = true, rot
        for i = 2, #g do g[i].oculto = true end
      end
    end
  end
  local out = {}
  for _, it in ipairs(itens) do if not it.oculto then out[#out + 1] = it end end
  return out
end

local function linhaEvento(it, ag)
  local e = it.e
  local L = {tipo = 'ev', chave = 'ev:' .. tostring(e.id)}
  if it.allDay then L.tm = 'dia todo'
  elseif it.ini <= ag then L.tm, L.agora = 'agora', true
  else L.tm = comum.hhmm(it.ini) end
  local titulo = S.privado and 'Compromisso' or tostring(e.title or '')
  L.tt = titulo
  local quando = it.allDay and 'dia todo' or (comum.hhmm(it.ini) .. ' às ' .. comum.hhmm(it.fim))
  L.tip = titulo .. ' · ' .. quando .. ' · ' .. tostring(e.source or '')
  L.cor = corFonte(e.source)
  L.rec = e.recurring == true
  L.rot = it.rot
  L.meet = comum.urlSegura(e.meetUrl)
  L.link = comum.urlSegura(e.link)
  return L
end

local function textoMais(n, fimDia)
  local d = os.date('*t', fimDia + 43200)
  local ate = d.day .. '/' .. d.month
  if n <= 0 then return 'nada mais até ' .. ate end
  if n == 1 then return 'mais 1 evento até ' .. ate end
  return 'mais ' .. n .. ' eventos até ' .. ate
end

-- Monta o conteúdo da Agenda no instante ag.
local function montar(ag)
  local C = {ag = ag, linhas = {}}
  C.dots, C.erro, C.pior = saude(ag)
  local itens, dia0, fimH = elegiveis(ag)
  itens = colapsar(itens, dia0)
  local L = C.linhas
  local function add(x) L[#L + 1] = x end
  add({tipo = 'g', chave = 'g:hoje', tt = 'Hoje'})
  local temHoje = false
  for _, it in ipairs(itens) do if it.dia == dia0 then temHoje = true; break end end
  if not temHoje then add({tipo = 'nada', chave = 'nada', tt = S.dados and 'nada mais hoje' or 'sem dados da agenda'}) end
  local mostrados, cur, maxFim = 0, dia0, nil
  local cap = NSLOT - 1
  for i, it in ipairs(itens) do
    if mostrados >= CFG.maxItems or #L + 3 > cap then break end
    if it.dia ~= cur then
      cur = it.dia
      add({tipo = 'g', chave = 'g:' .. os.date('%Y-%m-%d', cur + 43200), tt = rotuloDia(cur, dia0)})
    end
    add(linhaEvento(it, ag))
    mostrados = mostrados + 1
    -- vão livre: só hoje, entre eventos com hora mostrados, pelo maior fim acumulado
    if it.dia == dia0 and not it.allDay then
      maxFim = math.max(maxFim or it.fim, it.fim)
      local prox = itens[i + 1]
      if prox and prox.dia == dia0 and not prox.allDay and mostrados < CFG.maxItems
        and prox.ini - maxFim >= CFG.vaoMin * 60 then
        add({tipo = 'gap', chave = 'gap:' .. tostring(it.e.id),
          tt = 'livre ' .. comum.hhmm(maxFim) .. ' às ' .. comum.hhmm(prox.ini) .. ', ' .. comum.duracao((prox.ini - maxFim) / 60)})
      end
    end
  end
  if S.dados then
    add({tipo = 'mais', chave = 'mais', tt = textoMais(#itens - mostrados, fimH - 86400)})
  end
  -- posições
  local y = Y_LISTA
  if #C.erro > 0 then y = y + 6 end
  C.yLista = y
  for _, x in ipairs(L) do
    x.y = y
    y = y + ALT[x.tipo]
  end
  C.hLista = y
  return C
end

-- assinatura de uma linha: se muda, a linha faz crossfade
local function assinatura(x)
  if not x then return '' end
  return table.concat({x.tipo, x.chave, num(x.y), x.tm or '', x.agora and '1' or '0', x.tt or '', x.cor or '',
    x.rec and '1' or '0', x.rot or '', x.meet or '', x.link or '', x.tip or ''}, '|')
end

-- ---------------------------------------------------------------- desenho: slots
local function nomes(i) return 'Bg' .. i, 'Tm' .. i, 'Tt' .. i, 'Ro' .. i, 'Rc' .. i, 'Vd' .. i end

local function esconderSlot(i)
  for _, m in ipairs({nomes(i)}) do bang('!HideMeter', m) end
  bang('!SetOption', 'Bg' .. i, 'LeftMouseUpAction', '')
end

local function medir(m)
  bang('!ShowMeter', m)
  bang('!UpdateMeter', m)
  return SKIN:GetMeter(m):GetW() / CFG.scale
end

-- escreve o conteúdo x no slot i (textos, fontes, ações) e mede o que precisa de largura
local function aplicarSlot(i, x)
  local bg, tm, tt, ro, rc, vd = nomes(i)
  if SLOT[i] then SLOT[i].ult = nil end
  S.sujo = true
  if not x then esconderSlot(i); return end
  x.lay = {}
  if x.tipo == 'g' then
    bang('!SetOption', tt, 'FontFace', CFG.fonteDisplay)
    bang('!SetOption', tt, 'FontWeight', '650')
    bang('!SetOption', tt, 'FontSize', num(13 * 0.75 * CFG.scale))
    bang('!SetOption', tt, 'X', num(sc(24)))
    bang('!SetOption', tt, 'W', num(sc(332)))
  elseif x.tipo == 'ev' then
    bang('!SetOption', tt, 'FontFace', CFG.fonteTexto)
    bang('!SetOption', tt, 'FontWeight', '550')
    bang('!SetOption', tt, 'FontSize', num(15 * 0.75 * CFG.scale))
    bang('!SetOption', tt, 'X', num(sc(118)))
  else
    bang('!SetOption', tt, 'FontFace', CFG.fonteTexto)
    bang('!SetOption', tt, 'FontWeight', '400')
    bang('!SetOption', tt, 'FontSize', num(13.5 * 0.75 * CFG.scale))
    bang('!SetOption', tt, 'X', num(sc(x.tipo == 'gap' and 118 or 24)))
    bang('!SetOption', tt, 'W', num(sc(x.tipo == 'gap' and 238 or 332)))
  end
  bang('!SetOption', tt, 'Text', comum.textoSeguro(x.tt))
  bang('!SetOption', tt, 'ToolTipText', x.tipo == 'ev' and comum.textoSeguro(x.tip) or '')
  bang('!ShowMeter', tt)
  if x.tipo ~= 'ev' then
    for _, m in ipairs({tm, ro, rc, vd}) do bang('!HideMeter', m) end
    bang('!SetOption', bg, 'LeftMouseUpAction', '')
    bang('!SetOption', bg, 'ToolTipText', '')
    if x.tipo == 'gap' then bang('!ShowMeter', bg) else bang('!HideMeter', bg) end
    return
  end
  -- evento: hora (ou pílula "agora")
  if x.agora then
    bang('!SetOption', tm, 'FontFace', CFG.fonteTexto)
    bang('!SetOption', tm, 'FontWeight', '700')
    bang('!SetOption', tm, 'FontSize', num(12 * 0.75 * CFG.scale))
    bang('!SetOption', tm, 'X', num(sc(33)))
  else
    bang('!SetOption', tm, 'FontFace', CFG.fonteMono)
    bang('!SetOption', tm, 'FontWeight', '400')
    bang('!SetOption', tm, 'FontSize', num(13 * 0.75 * CFG.scale))
    bang('!SetOption', tm, 'X', num(sc(24)))
  end
  bang('!SetOption', tm, 'Text', x.tm)
  x.lay.pillW = medir(tm) + 18
  -- direita para a esquerda: vídeo, ♻, rótulo da série
  local dir = 356
  if x.meet then
    x.lay.vd = dir - 7.5
    dir = dir - 15 - 8
    bang('!SetOption', vd, 'X', num(sc(x.lay.vd)))
    bang('!SetOption', vd, 'LeftMouseUpAction', '[' .. x.meet .. ']')
    bang('!ShowMeter', vd)
  else
    bang('!SetOption', vd, 'LeftMouseUpAction', '')
    bang('!HideMeter', vd)
  end
  if x.rec then
    x.lay.rc = dir - 7.5
    dir = dir - 15 - 6
    bang('!SetOption', rc, 'X', num(sc(x.lay.rc)))
    bang('!ShowMeter', rc)
  else
    bang('!HideMeter', rc)
  end
  if x.rot then
    bang('!SetOption', ro, 'Text', x.rot)
    bang('!SetOption', ro, 'X', num(sc(dir)))
    local w = medir(ro)
    dir = dir - w - 8
  else
    bang('!HideMeter', ro)
  end
  if dir == 356 then dir = 356 - 4 end
  bang('!SetOption', tt, 'W', num(sc(math.max(40, dir - 118))))
  bang('!SetOption', bg, 'LeftMouseUpAction', x.link and ('[' .. x.link .. ']') or '')
  bang('!SetOption', bg, 'ToolTipText', comum.textoSeguro(x.tip))
  bang('!ShowMeter', bg)
end

-- desenha o slot i com alfa a, deslocamento dy e hover hv
local function desenharSlot(i, a, dy, hv)
  local x = SLOT[i] and SLOT[i].c
  if not x then return end
  local bg, tm, tt, ro, rc, vd = nomes(i)
  local cy = x.y + CENTRO[x.tipo] + dy
  local on, onv = cor('CorOn'), cor('CorOnV')
  if x.tipo == 'g' then
    bang('!SetOption', tt, 'FontColor', anim.alfa(onv, 255, a))
    bang('!SetOption', tt, 'Y', num(sc(cy)))
    return
  end
  if x.tipo ~= 'ev' then
    bang('!SetOption', tt, 'FontColor', anim.alfa(onv, 255, a))
    bang('!SetOption', tt, 'Y', num(sc(cy)))
    if x.tipo == 'gap' then
      -- pontilhado: 2 px, on-v a 55 % (meter na posição da linha: o retângulo do meter fica justo)
      bang('!SetOption', bg, 'X', num(sc(24)))
      bang('!SetOption', bg, 'Y', num(sc(cy - 2)))
      bang('!SetOption', bg, 'Shape', string.format(
        'Line %s,%s,%s,%s | StrokeWidth %s | Stroke Color %s | StrokeDashes 0.01,2 | StrokeDashCap Round | StrokeStartCap Round | StrokeEndCap Round',
        num(sc(1)), num(sc(2)), num(sc(79)), num(sc(2)), num(sc(2)), anim.alfa(onv, 140, a)))
      bang('!SetOption', bg, 'Shape2', '')
      bang('!SetOption', bg, 'Shape3', '')
    end
    return
  end
  -- fundo do hover: on a 7 % (alfa 1 em repouso: pixel 100 % transparente não recebe o mouse)
  -- O meter fica na posição da linha e as formas em coordenadas locais: o retângulo do meter (que é
  -- a área do ToolTipText) fica do tamanho da linha. Com X=0,Y=0 ele cobriria tudo acima dela.
  local r = 12 + 7 * hv
  local y0 = x.y + dy
  local ly = CENTRO.ev
  bang('!SetOption', bg, 'X', num(sc(16)))
  bang('!SetOption', bg, 'Y', num(sc(y0)))
  bang('!SetOption', bg, 'Shape', string.format('Rectangle 0,0,%s,%s,%s | Fill Color %s | StrokeWidth 0',
    num(sc(348)), num(sc(ALT.ev)), num(sc(r)),
    anim.alfa(on, math.max(1, 18 * hv), a)))
  bang('!SetOption', bg, 'Shape2', string.format('Ellipse %s,%s,%s | Fill Color %s | StrokeWidth 0',
    num(sc(103 - 16)), num(sc(ly)), num(sc(5)), anim.alfa(x.cor, 255, a)))
  if x.agora then
    local ph = 23
    bang('!SetOption', bg, 'Shape3', string.format('Rectangle %s,%s,%s,%s,%s | Fill Color %s | StrokeWidth 0',
      num(sc(24 - 16)), num(sc(ly - ph / 2)), num(sc(x.lay.pillW)), num(sc(ph)), num(sc(ph / 2)), anim.alfa(cor('CorSol'), 255, a)))
    bang('!SetOption', tm, 'FontColor', anim.alfa(cor('CorOnSol'), 255, a))
  else
    bang('!SetOption', bg, 'Shape3', '')
    bang('!SetOption', tm, 'FontColor', anim.alfa(onv, 255, a))
  end
  bang('!SetOption', tm, 'Y', num(sc(cy)))
  bang('!SetOption', tt, 'FontColor', anim.alfa(on, 255, a))
  bang('!SetOption', tt, 'Y', num(sc(cy)))
  for _, m in ipairs({ro, rc, vd}) do
    bang('!SetOption', m, 'FontColor', anim.alfa(onv, 255, a))
    bang('!SetOption', m, 'Y', num(sc(cy)))
  end
end

-- faixa de erro (SLOT[0])
local function aplicarErro(x)
  if SLOT[0] then SLOT[0].ult = nil end
  S.sujo = true
  if not x then
    bang('!HideMeter', 'ErroBg'); bang('!HideMeter', 'ErroTx')
    return
  end
  bang('!SetOption', 'ErroTx', 'Text', comum.textoSeguro(table.concat(x.linhas, '\n')))
  bang('!SetOption', 'ErroTx', 'Y', num(sc(x.y + 12)))
  bang('!ShowMeter', 'ErroTx')
  bang('!UpdateMeter', 'ErroTx')
  x.h = SKIN:GetMeter('ErroTx'):GetH() / CFG.scale + 24
  -- nasce transparente: quem dá o alfa é desenharErro (na entrada da faixa ela vem em fade, e a
  -- faixa velha, com a cor da última vez que existiu, nunca pisca)
  bang('!SetOption', 'ErroTx', 'FontColor', '0,0,0,0')
  bang('!SetOption', 'ErroBg', 'Shape', 'Rectangle 0,0,0,0 | StrokeWidth 0')
  bang('!SetOption', 'ErroBg', 'Shape2', '')
  bang('!UpdateMeterGroup', 'Erro')
  bang('!ShowMeter', 'ErroBg')
end

local function desenharErro(a, dy)
  local x = SLOT[0] and SLOT[0].c
  if not x then return end
  local base = x.pior == 'critico' and cor('CorCritico') or cor('CorAlerta')
  local fundo = anim.cor(cor('CorS'), base, 0.16)
  bang('!SetOption', 'ErroBg', 'Shape', string.format('Rectangle %s,%s,%s,%s,%s | Fill Color %s | StrokeWidth 0',
    num(sc(16)), num(sc(x.y + dy)), num(sc(348)), num(sc(x.h)), num(sc(16)), anim.alfa(fundo, 255, a)))
  bang('!SetOption', 'ErroBg', 'Shape2', string.format('Ellipse %s,%s,%s | Fill Color %s | StrokeWidth 0',
    num(sc(35)), num(sc(x.y + dy + 22)), num(sc(5)), anim.alfa(base, 255, a)))
  bang('!SetOption', 'ErroTx', 'FontColor', anim.alfa(cor('CorOn'), 255, a))
  bang('!SetOption', 'ErroTx', 'Y', num(sc(x.y + 12 + dy)))
end

-- ---------------------------------------------------------------- desenho: cartão e cabeçalho
local function desenharCabecalho(Vv)
  bang('!SetOption', 'Cartao', 'Shape', string.format('Rectangle 0,0,%s,%s,%s | Fill Color %s | StrokeWidth 0',
    num(sc(W)), num(sc(Vv.h)), num(sc(32)), cor('CorS')))
  local ha = Vv.headA
  bang('!SetOption', 'Titulo', 'FontColor', anim.alfa(cor('CorOnV'), 255, ha))
  -- pontos: alinhados à direita, o último centrado em 302
  local n = #Vv.dots
  for k = 1, NDOT do
    local m = 'Saude' .. k
    local d = Vv.dots[k]
    if d then
      -- meter de 14 x 14 centrado no ponto (área do tooltip justa; cada ponto tem o seu)
      local cx = 302 - (n - k) * 14
      bang('!SetOption', m, 'X', num(sc(cx - 7)))
      bang('!SetOption', m, 'Y', num(sc(35)))
      bang('!SetOption', m, 'Shape', string.format('Rectangle 0,0,%s,%s | Fill Color 0,0,0,1 | StrokeWidth 0', num(sc(14)), num(sc(14))))
      bang('!SetOption', m, 'Shape2', string.format('Ellipse %s,%s,%s | Fill Color %s | StrokeWidth 0',
        num(sc(7)), num(sc(7)), num(sc(d.r)), anim.alfa(d.cor, 255, ha)))
      bang('!SetOption', m, 'ToolTipText', comum.textoSeguro(d.tip or ''))
      bang('!ShowMeter', m)
    else
      bang('!HideMeter', m)
    end
  end
  -- cadeado: aberto = fundo on 8 %, ícone on-v, raio 20; fechado = fundo on, ícone s, raio 12
  local p = Vv.lockP
  local fundo = anim.cor(anim.alfa(cor('CorOn'), 20, 1), anim.alfa(cor('CorOn'), 255, 1), p)
  local fa = tonumber(fundo:match('(%d+)$'))
  bang('!SetOption', 'Cadeado', 'Shape', string.format('Rectangle 0,0,%s,%s,%s | Fill Color %s | StrokeWidth 0',
    num(sc(40)), num(sc(40)), num(sc(Vv.lockR)), anim.alfa(fundo, fa, ha)))
  bang('!SetOption', 'CadeadoIcone', 'FontColor', anim.alfa(anim.cor(cor('CorOnV'), cor('CorS'), p), 255, ha))
  -- Segoe Fluent Icons: E72E (Lock) / E785 (Unlock), em UTF-8 (como o ♻ do Dia)
  bang('!SetOption', 'CadeadoIcone', 'Text', S.privado and '\238\156\174' or '\238\158\133')
  bang('!SetOption', 'Cadeado', 'ToolTipText', S.privado and 'Modo privado ligado: títulos escondidos' or 'Modo privado (esconde os títulos)')
end

local function alvoCab(C)
  local dots = {}
  for k, d in ipairs(C.dots) do dots[k] = {cor = d.cor, r = d.cl == 'ok' and 4 or 5.4, tip = d.tip} end
  return {h = C.hLista + PAD_FIM + (C.erroH or 0), headA = 1, lockR = S.privado and 12 or 20,
    lockP = S.privado and 1 or 0, dots = dots}
end

-- ---------------------------------------------------------------- aplicar estado
-- a altura da faixa de erro só se sabe depois de medir: mede e empurra a lista para baixo
-- (protótipo: faixa a 6 px do cabeçalho, 4 px antes da lista)
local function posicionar(C)
  C.erroH = 0
  if #C.erro == 0 then
    C.erroSlot = nil
    aplicarErro(nil)
    return
  end
  local x = {tipo = 'erro', chave = 'erro', y = Y_LISTA + 6, linhas = C.erro, pior = C.pior}
  C.erroSlot = x
  aplicarErro(x)
  C.erroH = x.h + 4
  for _, l in ipairs(C.linhas) do l.y = l.y + C.erroH end
end

local function chaveCab(Vv)
  local t = {num(Vv.h), num(Vv.headA), num(Vv.lockR), num(Vv.lockP), S.privado and '1' or '0'}
  for _, d in ipairs(Vv.dots) do t[#t + 1] = d.cor .. '/' .. num(d.r) .. '/' .. tostring(d.tip) end
  return table.concat(t, '|')
end

-- Desenha só o que mudou desde o último quadro (alfa, deslocamento, hover, conteúdo) e atualiza só
-- os grupos desses meters: numa troca de 1 linha, 6 meters em vez de ~170.
local function redesenhar(tudo)
  local grupos = {}
  if V then
    local k = chaveCab(V)
    if tudo or k ~= S.cabUlt then S.cabUlt = k; desenharCabecalho(V); grupos[#grupos + 1] = 'Cab' end
  end
  local e = SLOT[0]
  if e and e.c then
    local k = num(e.a) .. '|' .. num(e.dy) .. '|' .. num(e.c.y) .. '|' .. num(e.c.h or 0)
    if tudo or k ~= e.ult then e.ult = k; desenharErro(e.a, e.dy); grupos[#grupos + 1] = 'Erro' end
  end
  for i = 1, NSLOT do
    local s = SLOT[i]
    if s and s.c then
      local k = num(s.a) .. '|' .. num(s.dy) .. '|' .. num(s.hv)
      if tudo or k ~= s.ult then s.ult = k; desenharSlot(i, s.a, s.dy, s.hv); grupos[#grupos + 1] = 'S' .. i end
    end
  end
  for _, g in ipairs(grupos) do bang('!UpdateMeterGroup', g) end
  if #grupos > 0 or S.sujo then
    S.sujo = false
    bang('!Redraw')
  end
end

local function copiarCab(t)
  local o = {h = t.h, headA = t.headA, lockR = t.lockR, lockP = t.lockP, dots = {}}
  for k, d in ipairs(t.dots) do o.dots[k] = {cor = d.cor, r = d.r, tip = d.tip} end
  return o
end

local function sigErro(x)
  if not x then return '' end
  return table.concat(x.linhas, '|') .. '|' .. x.pior .. '|' .. num(x.y)
end

-- estado final de C, sem animação (invisivel: aplica com alfa 0 e não desenha; a entrada desenha)
local function aplicarTudo(C, invisivel)
  local a = invisivel and 0 or 1
  for i = 1, NSLOT do
    local x = C.linhas[i]
    SLOT[i] = SLOT[i] or {a = 1, dy = 0, hv = 0}
    SLOT[i].c, SLOT[i].a, SLOT[i].dy = x, a, 0
    SLOT[i].sig = assinatura(x)
    if not x then SLOT[i].hv = 0 end
    aplicarSlot(i, x)
  end
  SLOT[0] = {c = C.erroSlot, a = a, dy = 0, hv = 0, sig = sigErro(C.erroSlot)}
  V = alvoCab(C)
  E = C
  if not invisivel then redesenhar(true) end
end

-- ---------------------------------------------------------------- transição
local function iniciarTimer()
  -- o ActionTimer para sozinho depois de 120 repetições: flag velha (> 0,25 s sem passo) reinicia
  if S.timer and S.tPasso and os.clock() - S.tPasso < 0.25 then return end
  S.timer = true
  S.tPasso = os.clock()
  bang('!CommandMeasure', 'mAT', 'Execute 1')
end

local function pararTimer()
  if not S.timer then return end
  S.timer = false
  bang('!CommandMeasure', 'mAT', 'Stop 1')
end

local function terminar()
  if not A then return end
  local C = A.novo
  A = nil
  aplicarTudo(C)
end

-- quadro da transição no instante s
local function quadro(s)
  local para = A.para
  if A.entrada then
    -- entrada escalonada: linhas sobem 10 px e aparecem pela mola 'row'
    local vh = copiarCab(para)
    vh.headA = math.min(1, anim.valor(mRow, s) * 1.6)
    V = vh
    if SLOT[0].c then
      local x = anim.valor(mRow, s)
      SLOT[0].a, SLOT[0].dy = math.min(1, x * 1.4), (1 - x) * 10
    end
    for i = 1, NSLOT do
      local sl = SLOT[i]
      if sl.c then
        local x = anim.valor(mRow, s - A.passo * i)
        sl.a, sl.dy = anim.limitar(x * 1.4, 0, 1), (1 - x) * 10
      end
    end
    redesenhar()
    return
  end
  -- troca: linhas que mudaram saem (110 ms) e as novas entram 4 px abaixo (220 ms)
  local entra = anim.saida((s - T_SAI) / T_ENTRA)
  if s >= T_SAI and not A.trocou then
    A.trocou = true
    for i, ch in pairs(A.muda) do
      if i == 0 then
        SLOT[0].c = ch.para
        if not ch.para then aplicarErro(nil) end
      else
        SLOT[i].c = ch.para
        SLOT[i].hv = 0
        aplicarSlot(i, ch.para)
      end
    end
  end
  for i, ch in pairs(A.muda) do
    local sl = SLOT[i]
    if s < T_SAI then
      local q = s / T_SAI
      sl.a, sl.dy = ch.de and (1 - q * q) or 0, 0
    else
      sl.a, sl.dy = entra, 4 * (1 - entra)
    end
  end
  -- cartão: cresce desde o início; encolhe só depois que a linha velha sumiu
  local vh = copiarCab(para)
  local de = A.de
  if para.h > de.h then
    vh.h = de.h + (para.h - de.h) * anim.saida(s / (T_SAI + T_ENTRA * 0.6))
  else
    vh.h = de.h + (para.h - de.h) * entra
  end
  local pb = anim.valor(mBoing, s)
  local pc = anim.saida(s / T_COR)
  vh.lockR = de.lockR + (para.lockR - de.lockR) * pb
  vh.lockP = de.lockP + (para.lockP - de.lockP) * pc
  for k, d in ipairs(vh.dots) do
    local d0 = de.dots[k]
    if d0 then
      d.cor = anim.cor(d0.cor, d.cor, pc)
      d.r = d0.r + (d.r - d0.r) * pb
    end
  end
  V = vh
  redesenhar()
end

-- compara E (atual) com C (novo) e anima só o que mudou
local function transicao(C, opcoes)
  opcoes = opcoes or {}
  if A then terminar() end
  if not E or opcoes.entrada then
    -- aplica tudo invisível e sobe em cascata (escalonamento total ≤ 150 ms + mola ~0,3 s)
    if not animando() then aplicarTudo(C); return end
    aplicarTudo(C, true)
    local n = 0
    for i = 1, NSLOT do if SLOT[i].c then n = i end end
    A = {entrada = true, novo = C, para = alvoCab(C), dur = 0,
      passo = n > 1 and math.min(0.035, 0.15 / (n - 1)) or 0}
    A.dur = A.passo * n + mRow.dur
    A.t0 = os.clock()
    quadro(0)
    iniciarTimer()
    return
  end
  local muda, alguma = {}, false
  for i = 1, NSLOT do
    local x = C.linhas[i]
    local sig = assinatura(x)
    if sig ~= SLOT[i].sig then
      muda[i] = {de = SLOT[i].c, para = x}
      SLOT[i].sig = sig
      alguma = true
    end
  end
  local se = sigErro(C.erroSlot)
  if se ~= SLOT[0].sig then
    muda[0] = {de = SLOT[0].c, para = C.erroSlot}
    SLOT[0].sig = se
    alguma = true
  end
  local para = alvoCab(C)
  local cabMudou = para.lockP ~= V.lockP or #para.dots ~= #V.dots
  for k, d in ipairs(para.dots) do
    local d0 = V.dots[k]
    if not d0 or d0.cor ~= d.cor or d0.r ~= d.r or d0.tip ~= d.tip then cabMudou = true end
  end
  E = C
  if not alguma and not cabMudou and para.h == V.h then return end
  if not animando() then
    aplicarTudo(C)
    return
  end
  A = {muda = muda, novo = C, de = copiarCab(V), para = para, t0 = os.clock(),
    dur = math.max(T_SAI + T_ENTRA, cabMudou and math.max(mBoing.dur, T_COR) or 0)}
  -- a faixa de erro nova precisa do texto já medido para a altura do cartão: ela mede em posicionar()
  quadro(0)
  iniciarTimer()
end

-- ---------------------------------------------------------------- ciclo
local function checar(opcoes)
  local C = montar(agora())
  posicionar(C)
  -- posicionar() já escreveu a faixa nova nos meters; se ela não for animar, redesenha agora
  transicao(C, opcoes)
end

local function lerAgenda(forcar)
  S.leitor.caminho = comum.caminhoAgenda()   -- !SetVariable DebugAgenda vale sem refresh
  local erroAntes = S.leitor.erro
  local d, mudou = S.leitor:ler(forcar)
  if d and mudou then
    S.dados = d
    S.animSistema = not (type(d.ambiente) == 'table' and d.ambiente.animacoes == false)
    comum.log('info', 'agenda lida: ' .. tostring(type(d.events) == 'table' and #d.events or 0) .. ' eventos')
  end
  return mudou or (S.leitor.erro ~= erroAntes)
end

local function seguro(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    if comum then comum.log('erro', err) else print('Horizonte Agenda: ' .. tostring(err)) end
  end
end

function Initialize()
  seguro(function()
    local carregar = dofile(SKIN:GetVariable('@') .. 'Lua\\carregar.lua')
    comum = carregar('comum')
    anim = carregar('anim')
    comum.iniciar('Agenda')
    mRow = anim.nomeada('row', 0.01)
    mBoing = anim.nomeada('boing', 0.01)
    CFG.scale = tonumber(var('Scale', '1')) or 1
    CFG.maxItems = math.max(1, tonumber(var('MaxItems', '8')) or 8)
    CFG.vaoMin = tonumber(var('VaoMin', '45')) or 45
    CFG.dias = tonumber(var('DiasLista', '14')) or 14
    CFG.ocultas = var('FontesOcultas', 'feriados')
    CFG.releitura = tonumber(var('ReleituraS', '60')) or 60
    CFG.fonteDisplay = var('FonteDisplay', 'Segoe UI Variable Display')
    CFG.fonteTexto = var('FonteTexto', 'Segoe UI Variable Text')
    CFG.fonteMono = var('FonteMono', 'Cascadia Mono')
    CFG.cor = {}
    for _, k in ipairs({'CorS', 'CorOn', 'CorOnV', 'CorSol', 'CorOnSol', 'CorAgPes', 'CorAgCor', 'CorAgFer',
      'CorAlerta', 'CorCritico'}) do
      CFG.cor[k] = var(k, '128,128,128')
    end
    S.animVar = var('Animacoes', '1') ~= '0'
    S.privado = var('Privado', '0') == '1'
    S.forcada = hhmmParaSeg(var('DebugHora', ''))
    S.leitor = comum.leitor(comum.caminhoAgenda(), {schemaVersion = 1})
    for i = 0, NSLOT do SLOT[i] = {a = 1, dy = 0, hv = 0, sig = nil} end
    bang('!SetOption', 'Titulo', 'Text', 'Próximos ' .. CFG.dias .. ' dias')
    lerAgenda(true)
  end)
end

function Update()
  if not comum then return '' end
  seguro(function()
    if not S.pronto then
      S.pronto = true
      S.minuto = math.floor(agora() / 60)
      checar({entrada = true})
      return
    end
    S.seg = S.seg + 1
    local mudou = false
    if S.seg >= CFG.releitura then S.seg = 0; mudou = lerAgenda(false) end
    if A then return end
    local m = math.floor(agora() / 60)
    if mudou or m ~= S.minuto then
      S.minuto = m
      checar()
    end
  end)
  return E and #E.linhas or 0
end

-- Passo do ActionTimer (~16 ms pedidos; o tempo real vem de os.clock)
function Passo()
  seguro(function()
    local t = os.clock()
    local dt = t - (S.tPasso or t)
    S.tPasso = t
    local hoverAndando = false
    for i = 1, NSLOT do
      local sl = SLOT[i]
      local alvo = (S.sobre == i and sl.c and sl.c.tipo == 'ev') and 1 or 0
      if sl.hv ~= alvo then
        local passo = dt / T_HOVER
        if alvo > sl.hv then sl.hv = math.min(alvo, sl.hv + passo) else sl.hv = math.max(alvo, sl.hv - passo) end
        hoverAndando = true
      end
    end
    if A and A.t0 then
      local s = t - A.t0
      if s >= A.dur then terminar() else quadro(s) end
    elseif hoverAndando then
      redesenhar()
    end
    if not A and not hoverAndando then pararTimer() end
  end)
end

-- Hover: Sobre(i) ao entrar na linha i, Sobre(-i) ao sair
function Sobre(i)
  seguro(function()
    i = tonumber(i) or 0
    if i > 0 then S.sobre = i elseif S.sobre == -i then S.sobre = 0 end
    if animando() then
      iniciarTimer()
    else
      for k = 1, NSLOT do
        local sl = SLOT[k]
        local alvo = (S.sobre == k and sl.c and sl.c.tipo == 'ev') and 1 or 0
        if sl.hv ~= alvo then sl.hv = alvo end
      end
      redesenhar()
    end
  end)
end

-- Cadeado: liga/desliga o modo privado e grava no Local.inc (cria o arquivo se não existir)
function AlternarPrivado()
  seguro(function()
    S.privado = not S.privado
    local v = S.privado and '1' or '0'
    local caminho = SKIN:GetVariable('@') .. 'Local.inc'
    local f = io.open(caminho, 'rb')
    if f then
      f:close()
    else
      -- !WriteKeyValue não cria arquivo: nasce em UTF-16 LE com BOM, como o resto do skin
      local nf = io.open(caminho, 'wb')
      if nf then
        local txt = '[Variables]\r\n'
        local b = {'\255\254'}
        for k = 1, #txt do b[#b + 1] = txt:sub(k, k) .. '\0' end
        nf:write(table.concat(b))
        nf:close()
      end
    end
    bang('!WriteKeyValue', 'Variables', 'Privado', v, caminho)
    bang('!SetVariable', 'Privado', v)
    -- o Dia mostra o título do próximo evento em destaque: avisa (config descarregada ignora o bang)
    bang('!SetVariable', 'Privado', v, 'Horizonte\\Dia')
    bang('!CommandMeasure', 'mLeitor', 'Privado(' .. v .. ')', 'Horizonte\\Dia')
    comum.log('info', 'modo privado ' .. v)
    if S.pronto then checar() end
  end)
end

-- Chamado pelo agenda_sync depois de gravar o agenda.json
function Recarregar()
  seguro(function()
    lerAgenda(true)
    if S.pronto then checar() end
  end)
end

-- Repete a entrada (menu de contexto)
function Entrada()
  seguro(function()
    if A then terminar() end
    checar({entrada = true})
  end)
end

-- Depuração: esquece o último estado bom e relê (prova "arquivo ausente desde o início").
function Esquecer()
  seguro(function()
    S.dados = nil
    S.leitor = comum.leitor(comum.caminhoAgenda(), {schemaVersion = 1})
    lerAgenda(true)
    if A then terminar() end
    checar()
  end)
end

-- Depuração: congela a hora ('14:37') e anima a troca; '' volta à hora real.
function Forcar(hhmm)
  seguro(function()
    S.forcada = hhmmParaSeg(hhmm)
    if A then terminar() end
    S.minuto = math.floor(agora() / 60)
    checar()
  end)
end
