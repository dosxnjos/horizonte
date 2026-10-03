-- Horizonte\Dia: cartão que muda de papel (PRÓXIMO, URGENTE, AGORA, LIVRE) + linha do dia.
-- Arquivo em UTF-16 LE com BOM (assim os acentos chegam certos aos meters).
-- Measure "mLeitor": o agenda_sync chama Recarregar() depois de gravar o agenda.json.
-- Depuração (docs/widgets.md § Dia): DebugHora=HH:MM, Forcar('HH:MM'), Quadro('14:44','14:46',0.3).
--
-- Regra de título real: este script nunca grava título de evento em log.

local comum, anim
local mForma, mBoing, mEsp
local CFG = {}
local A = nil          -- transição em curso
local V = nil          -- visual atual (o que está desenhado)
local E = nil          -- conteúdo atual (textos, eventos, linha)
local S = {
  pronto = false,
  forcada = nil,       -- segundos desde a meia-noite (depuração)
  minuto = nil,        -- último minuto calculado
  seg = 0, segSnap = 0,
  dados = nil, snap = nil,
  animVar = true, animSistema = true,
  privado = false,     -- variável Privado (cadeado da Agenda): títulos viram "Compromisso"
}

local W = 430          -- largura lógica do cartão
local H_BASE = 268     -- altura sem aviso
local H_AVISO = 284    -- altura com a linha de aviso
local MAX_BLOCOS = 12
local MAX_HORAS = 9

-- tempos da transição (s): saída do texto, entrada, cor
local T_SAI = 0.15
local T_COR = 0.45
local T_FLASH = 0.10

local PAPEL = {
  proximo = {bg = 'CorSHi', on = 'CorOn', r = {32, 32, 32, 32}},
  urgente = {bg = 'CorSold', on = 'CorOnSold', r = {22, 22, 22, 22}},
  agora = {bg = 'CorSol', on = 'CorOnSol', r = {56, 14, 56, 14}},
  livre = {bg = 'CorCalm', on = 'CorOnCalm', r = {72, 72, 72, 72}},
}

local ROTULO_STATUS = {offline = 'offline', formato = 'feed inválido', sem_credencial = 'sem credencial'}
local COR_FONTE = {pessoal = 'CorAgPes', corporativo = 'CorAgCor', feriados = 'CorAgFer'}

local function bang(...) SKIN:Bang(...) end
local num = function(x) return string.format('%.2f', x) end
local function var(nome, padrao)
  local v = SKIN:GetVariable(nome, padrao)
  if v == nil or v == '' then return padrao end
  return v
end
local function animando() return S.animVar and S.animSistema end
local function sc(x) return x * CFG.scale end

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
local function minutosAte(t, ag) return math.ceil((t - ag) / 60 - 1e-9) end

-- ---------------------------------------------------------------- conteúdo (o que o cartão diz)
local function nomeFonte(id)
  if not S.dados or type(S.dados.sources) ~= 'table' then return id end
  for _, f in ipairs(S.dados.sources) do
    if f.id == id then return (f.id or f.nome or id) end
  end
  return id
end

local function corFonte(id)
  local tok = COR_FONTE[id]
  if tok then return CFG.cor[tok] end
  if S.dados and type(S.dados.sources) == 'table' then
    for _, f in ipairs(S.dados.sources) do
      if f.id == id then return comum.corHex(f.cor) or CFG.cor.CorOnV end
    end
  end
  return CFG.cor.CorOnV
end

local function eventosComHora()
  local out = {}
  if not S.dados or type(S.dados.events) ~= 'table' then return out end
  for _, e in ipairs(S.dados.events) do
    if type(e) == 'table' and not e.allDay and tonumber(e.start) and tonumber(e['end']) then
      out[#out + 1] = e
    end
  end
  return out
end

local function linhaAviso()
  local partes = {}
  local L = S.leitorAg
  if S.dados and L.erro == 'sem arquivo' then
    partes[#partes + 1] = 'agenda.json sumiu, mostrando a última leitura'
  elseif S.dados and L.erro then
    partes[#partes + 1] = 'agenda.json ilegível, mostrando a última leitura'
  end
  if S.dados and type(S.dados.sources) == 'table' then
    local hoje0 = comum.inicioDoDia(agora())
    for _, f in ipairs(S.dados.sources) do
      if type(f) == 'table' and f.status and f.status ~= 'ok' then
        local st = ROTULO_STATUS[f.status] or (tostring(f.status):match('^http(%d+)$') and ('erro ' .. f.status:sub(5))) or tostring(f.status)
        local txt = tostring(f.id or f.nome or '?') .. ' ' .. st
        local ok = tonumber(f.lastOkAt)
        if ok and f.status ~= 'sem_credencial' then
          if ok >= hoje0 then txt = txt .. ', dados de ' .. comum.hhmm(ok)
          else txt = txt .. ', dados de ' .. os.date('%d/%m', ok) end
        end
        partes[#partes + 1] = txt
      end
    end
  end
  if #partes == 0 then return nil end
  return table.concat(partes, ' · ')
end

-- Reset da janela 5h da conta Active (snapshot do tray). nil se não houver.
local function resetClaude()
  local s = S.snap
  if type(s) ~= 'table' or type(s.accounts) ~= 'table' then return nil end
  for _, c in ipairs(s.accounts) do
    if type(c) == 'table' and c.Active == true and type(c.Bars) == 'table' then
      for _, b in ipairs(c.Bars) do
        if type(b) == 'table' and b.Label == '5h' then return comum.epochIso(b.ResetsAt) end
      end
    end
  end
  return nil
end

-- Título do evento; no modo privado (cadeado da Agenda, variável Privado) vira "Compromisso",
-- inclusive no tooltip, como na Agenda.
local function tituloDe(ev)
  if S.privado then return 'Compromisso' end
  return tostring(ev.title or '')
end

local function textoProximoFuturo(ev, ag)
  -- "amanhã " / "seg 05/10 " + hora + título
  local amanha0 = comum.inicioDoDia(ag, 1)
  local quando
  if ev.start < amanha0 + 86400 then quando = 'amanhã '
  else quando = comum.diaCurtoData(os.date('%Y-%m-%d', ev.start)) .. ' ' end
  return quando, comum.hhmm(ev.start), ' ' .. tituloDe(ev), ev.recurring == true
end

-- Monta o conteúdo do cartão no instante ag.
local function calcular(ag)
  local C = {meta = {'', '', '', ''}, metaY = 127, onda = false, btn = 'off'}
  local dia0, dia1 = comum.inicioDoDia(ag), comum.inicioDoDia(ag, 1)
  local evs = eventosComHora()
  local hoje = {}
  for _, e in ipairs(evs) do
    if e['end'] > dia0 and e.start < dia1 then hoje[#hoje + 1] = e end
  end
  C.hoje, C.dia0, C.ag = hoje, dia0, ag
  C.aviso = linhaAviso()
  C.reset = resetClaude()

  if not S.dados then
    C.papel, C.chave = 'proximo', 'semagenda'
    C.kick = 'Agenda'
    C.titulo = 'agenda indisponível'
    C.meta[3] = 'o agenda-sync ainda não gravou o agenda.json'
    return C
  end

  -- AGORA: eventos em curso (o principal é o que começou por último)
  local atuais = {}
  for _, e in ipairs(hoje) do
    if e.start <= ag and ag < e['end'] then atuais[#atuais + 1] = e end
  end
  if #atuais > 0 then
    table.sort(atuais, function(a, b)
      if a.start ~= b.start then return a.start > b.start end
      return a['end'] < b['end']
    end)
    local ev = atuais[1]
    C.papel, C.ev = 'agora', ev
    C.chave = 'agora:' .. tostring(ev.id) .. ':' .. #atuais
    C.kick = #atuais > 1 and ('Agora (' .. #atuais .. ')') or 'Agora'
    C.titulo = tituloDe(ev)
    C.meta = {'termina ', comum.hhmm(ev['end']), ', faltam ' .. comum.duracao(minutosAte(ev['end'], ag)), ''}
    C.metaY = 160
    C.onda = true
    C.prog = (ag - ev.start) / math.max(60, ev['end'] - ev.start)
    -- Entrar: a chamada do principal; sem ela, a de outro evento em curso (sobreposição)
    for _, e in ipairs(atuais) do
      if comum.urlSegura(e.meetUrl) then C.meet = e.meetUrl; break end
    end
    C.btn = C.meet and 'lit' or 'off'
    C.link = ev.link
    return C
  end

  -- próximo de hoje
  local prox
  for _, e in ipairs(hoje) do
    if e.start > ag then prox = e; break end
  end
  if prox then
    local inn = minutosAte(prox.start, ag)
    C.ev = prox
    local janela = comum.hhmm(prox.start) .. ' às ' .. comum.hhmm(prox['end']) .. ','
    local rec = prox.recurring == true and '\238\162\149' or ''
    if inn <= CFG.livreMin then
      C.papel = inn <= CFG.urgenteMin and 'urgente' or 'proximo'
      C.chave = C.papel .. ':' .. tostring(prox.id)
      C.kick = inn < CFG.emMin and ('Próximo, em ' .. comum.duracao(inn)) or ('Próximo, às ' .. comum.hhmm(prox.start))
      C.titulo = tituloDe(prox)
      C.meta = {'', janela, ' ' .. nomeFonte(prox.source), rec}
      if comum.urlSegura(prox.meetUrl) then
        C.meet = prox.meetUrl
        C.btn = inn <= CFG.acendeMin and 'lit' or 'dim'
      end
    else
      C.papel, C.chave = 'livre', 'livreate:' .. tostring(prox.id)
      C.kick = 'Livre'
      C.titulo = 'livre até ' .. comum.hhmm(prox.start) .. ', ' .. comum.duracao(inn)
      C.meta = {'depois ', comum.hhmm(prox.start), ' ' .. tituloDe(prox), rec}
      C.link = prox.link
    end
    if C.papel ~= 'livre' then C.link = prox.link end
    return C
  end

  -- LIVRE pelo resto do dia
  C.papel, C.chave, C.kick = 'livre', 'livre', 'Livre'
  local fim = nil
  for _, e in ipairs(hoje) do
    if e['end'] <= ag and (not fim or e['end'] > fim) then fim = e['end'] end
  end
  if fim and fim < dia1 then C.titulo = 'dia livre a partir de ' .. comum.hhmm(fim)
  else C.titulo = 'dia livre' end
  local fut
  for _, e in ipairs(evs) do
    if e.start >= dia1 then fut = e; break end
  end
  if fut then
    local q, h, t, rec = textoProximoFuturo(fut, ag)
    C.meta = {q, h, t, rec and '\238\162\149' or ''}
    C.link = fut.link
    C.chave = 'livre:' .. tostring(fut.id)
  else
    C.meta = {'', '', 'nada mais na agenda', ''}
  end
  return C
end

-- ---------------------------------------------------------------- linha do dia
local function faixa(C)
  local h0, h1 = CFG.linhaDe, CFG.linhaAte
  local agH = (C.ag - C.dia0) / 3600
  if agH < h0 then return 0, 24 end   -- madrugada: o dia inteiro
  for _, e in ipairs(C.hoje) do
    local s = math.max(0, (e.start - C.dia0) / 3600)
    local f = math.min(24, (e['end'] - C.dia0) / 3600)
    if s < h0 then h0 = math.floor(s) end
    if f > h1 then h1 = math.ceil(f) end
  end
  if agH > h1 then h1 = math.min(24, math.ceil(agH + 0.01)) end
  -- reset do Claude ainda hoje e depois do agora (ex.: 23:30): a régua alarga para mostrá-lo
  if C.reset and C.reset > C.ag and C.reset < C.dia0 + 86400 then
    local rH = (C.reset - C.dia0) / 3600
    if rH > h1 then h1 = math.min(24, math.ceil(rH + 0.01)) end
  end
  return math.max(0, h0), math.min(24, h1)
end

local function rotulosHora(h0, h1)
  local hs = {h0}
  for h = h0 + 1, h1 - 1 do
    if h % 3 == 0 and h - h0 >= 1.5 and h1 - h >= 1.5 then hs[#hs + 1] = h end
  end
  -- 7–21 dá 07, 09, 12, 15, 18, 21, igual ao protótipo
  hs[#hs + 1] = h1
  return hs
end

-- desenha trilho, blocos, agulha, reset e rótulos com a cor 'on' e alfa geral f.
-- mistura: quanto a cor da agenda vai para a cor 'on' (no fundo claro do AGORA, as cores pastel das
-- agendas somem; ali o bloco puxa 60 % para o texto, como o currentColor do protótipo)
local function desenharLinha(C, on, f, mistura)
  local h0, h1 = faixa(C)
  local x0, larg = 34, 362
  local function tx(t) return x0 + ((t - C.dia0) / 3600 - h0) / (h1 - h0) * larg end
  local ag = C.ag
  local shapes = {}
  shapes[1] = string.format('Line %s,%s,%s,%s | StrokeWidth %s | Stroke Color %s | StrokeStartCap Round | StrokeEndCap Round',
    num(sc(36)), num(sc(216)), num(sc(394)), num(sc(216)), num(sc(4)), anim.alfa(on, 51, f))
  local n = 0
  for _, e in ipairs(C.hoje) do
    if n >= MAX_BLOCOS then break end
    n = n + 1
    local a = math.max(e.start, C.dia0 + h0 * 3600)
    local b = math.min(e['end'], C.dia0 + h1 * 3600)
    local xa, xb = tx(a), tx(b)
    local w = math.max(8, xb - xa)
    if xb - xa < 8 then xa = (xa + xb) / 2 - 4 end
    local alfa = 158
    if ag >= e['end'] then alfa = 77 elseif ag >= e.start then alfa = 255 end
    shapes[#shapes + 1] = string.format('Rectangle %s,%s,%s,%s,%s | Fill Color %s | StrokeWidth 0',
      num(sc(xa)), num(sc(210)), num(sc(w)), num(sc(12)), num(sc(6)),
      anim.alfa(anim.cor(corFonte(e.source), on, mistura or 0), alfa, f))
  end
  -- reset do Claude: marca a próxima renovação dentro da faixa; já passada (snapshot velho) fica apagada
  local r = C.reset
  local rx = nil
  if r and r >= C.dia0 + h0 * 3600 and r <= C.dia0 + h1 * 3600 then
    rx = tx(r)
    local alfaR = r < ag and 0.35 or 0.8
    shapes[#shapes + 1] = string.format('Line %s,%s,%s,%s | StrokeWidth %s | Stroke Color %s | StrokeStartCap Round | StrokeEndCap Round',
      num(sc(rx)), num(sc(202)), num(sc(rx)), num(sc(208)), num(sc(1.5)), anim.alfa(on, 255 * 0.6 * alfaR, f))
    bang('!SetOption', 'Reset', 'X', num(sc(rx)))
    bang('!SetOption', 'Reset', 'FontColor', anim.alfa(on, 255 * alfaR, f))
    bang('!SetOption', 'Reset', 'ToolTipText', (r < ag and 'Claude renovou às ' or 'Claude renova às ') .. comum.hhmm(r))
    bang('!ShowMeter', 'Reset')
  else
    bang('!HideMeter', 'Reset')
  end
  -- agulha do agora
  local agT = math.max(C.dia0 + h0 * 3600, math.min(ag, C.dia0 + h1 * 3600))
  local nx = tx(agT)
  shapes[#shapes + 1] = string.format('Rectangle %s,%s,%s,%s,%s | Fill Color %s | StrokeWidth 0',
    num(sc(nx - 2)), num(sc(201)), num(sc(4)), num(sc(30)), num(sc(2)), anim.alfa(on, 255, f))
  -- grava os shapes (sobras viram vazias: o Shape para de ler na primeira chave vazia)
  for i = 1, MAX_BLOCOS + 3 do
    local k = i == 1 and 'Shape' or ('Shape' .. i)
    bang('!SetOption', 'Linha', k, shapes[i] or '')
  end
  -- rótulos de hora
  local hs = rotulosHora(h0, h1)
  for i = 1, MAX_HORAS do
    local m = 'Hora' .. i
    local h = hs[i]
    if h then
      local x, al = tx(C.dia0 + h * 3600), 'CenterCenter'
      if i == 1 then x, al = sc(34), 'LeftCenter' elseif i == #hs then x, al = sc(396), 'RightCenter' else x = sc(x) end
      bang('!SetOption', m, 'Text', string.format('%02d', h))
      bang('!SetOption', m, 'X', num(x))
      bang('!SetOption', m, 'StringAlign', al)
      bang('!SetOption', m, 'FontColor', anim.alfa(on, 199, f))
      bang('!ShowMeter', m)
    else
      bang('!HideMeter', m)
    end
  end
end

-- ---------------------------------------------------------------- desenho do cartão
local function contorno(w, h, r, esc)
  local x, y = W * (1 - esc) / 2, h * (1 - esc) / 2
  w, h = w * esc, h * esc
  local lim = math.min(w, h) / 2
  local q = {}
  for i = 1, 4 do q[i] = math.max(0.01, math.min(lim, r[i] * esc)) end
  local function p(a, b) return num(sc(a)) .. ',' .. num(sc(b)) end
  local function arco(a, b, rr) return 'ArcTo ' .. p(a, b) .. ',' .. num(sc(rr)) .. ',' .. num(sc(rr)) end
  return p(x, y + q[1]) .. ' | ' .. arco(x + q[1], y, q[1]) ..
    ' | LineTo ' .. p(x + w - q[2], y) .. ' | ' .. arco(x + w, y + q[2], q[2]) ..
    ' | LineTo ' .. p(x + w, y + h - q[3]) .. ' | ' .. arco(x + w - q[3], y + h, q[3]) ..
    ' | LineTo ' .. p(x + q[4], y + h) .. ' | ' .. arco(x, y + h - q[4], q[4]) .. ' | ClosePath 1'
end

local function desenharOnda(C, on, alfa, dy, amp)
  if not C.onda then bang('!HideMeter', 'Onda'); return end
  local y = 129.5
  local x0 = 28 + 2.5
  local larg = 374 - 5
  local f = anim.limitar(C.prog or 0, 0, 1)
  local x1 = x0 + f * larg
  local lam = 22
  local pts = {num(sc(x0)) .. ',' .. num(sc(y))}
  local x = x0 + 2
  while x < x1 do
    pts[#pts + 1] = 'LineTo ' .. num(sc(x)) .. ',' .. num(sc(y + amp * math.sin((x - x0) / lam * math.pi * 2)))
    x = x + 2
  end
  pts[#pts + 1] = 'LineTo ' .. num(sc(math.max(x1, x0 + 0.1))) .. ',' .. num(sc(y + amp * math.sin((x1 - x0) / lam * math.pi * 2)))
  bang('!SetOption', 'Onda', 'OndaP', table.concat(pts, ' | '))
  bang('!SetOption', 'Onda', 'Shape', string.format(
    'Path OndaP | StrokeWidth %s | Stroke Color %s | Fill Color 0,0,0,0 | StrokeStartCap Round | StrokeEndCap Round | StrokeLineJoin Round',
    num(sc(5)), anim.alfa(on, 255, alfa)))
  local t0, t1 = x1 + 5 + 4, 28 + 374 - 2.5
  if t0 < t1 then
    bang('!SetOption', 'Onda', 'Shape2', string.format(
      'Line %s,%s,%s,%s | StrokeWidth %s | Stroke Color %s | StrokeStartCap Round | StrokeEndCap Round',
      num(sc(t0)), num(sc(y)), num(sc(t1)), num(sc(y)), num(sc(5)), anim.alfa(on, 71, alfa)))
  else
    bang('!SetOption', 'Onda', 'Shape2', 'Line 0,0,0,0 | StrokeWidth 0 | Stroke Color 0,0,0,0')
  end
  bang('!SetOption', 'Onda', 'Shape3', string.format('Ellipse %s,%s,%s | Fill Color %s | StrokeWidth 0',
    num(sc(28 + 374 - 2.5)), num(sc(y)), num(sc(2.2)), anim.alfa(on, 255, alfa)))
  bang('!SetOption', 'Onda', 'Y', num(sc(dy)))
  bang('!ShowMeter', 'Onda')
end

-- posiciona Meta1..4 lado a lado (mede a largura de cada um; só quando o texto muda)
local function posicionarMeta(C, dy)
  local x = 28
  for i = 1, 4 do
    local m = 'Meta' .. i
    local txt = C.meta[i] or ''
    bang('!SetOption', m, 'Text', comum.textoSeguro(txt))
    bang('!SetOption', m, 'X', num(sc(x + (i == 4 and 5 or 0))))
    bang('!SetOption', m, 'Y', num(sc(C.metaY + dy)))
    if txt ~= '' then
      bang('!ShowMeter', m)
      bang('!UpdateMeter', m)
      x = x + (i == 4 and 5 or 0) + SKIN:GetMeter(m):GetW() / CFG.scale
      -- GetW não conta o espaço do fim ("termina "): soma a largura de um espaço a 14 px
      if txt:sub(-1) == ' ' then x = x + 4 end
    else
      bang('!HideMeter', m)
    end
  end
end

-- escreve os textos de C nos meters (só quando o conteúdo muda)
local function aplicarTextos(C)
  bang('!SetOption', 'Kick', 'Text', comum.textoSeguro(C.kick))
  bang('!SetOption', 'Titulo', 'Text', comum.textoSeguro(C.titulo))
  bang('!SetOption', 'Titulo', 'ToolTipText', comum.textoSeguro(C.titulo))
  local url = comum.urlSegura(C.link)
  bang('!SetOption', 'Titulo', 'LeftMouseUpAction', url and ('[' .. url .. ']') or '')
  local meet = comum.urlSegura(C.meet)
  bang('!SetOption', 'Botao', 'LeftMouseUpAction', meet and ('[' .. meet .. ']') or '')
  bang('!SetOption', 'Botao', 'ToolTipText', C.btn == 'lit' and 'Entrar na videochamada' or 'Videochamada (acende 10 min antes)')
  if C.aviso then
    bang('!SetOption', 'AvisoTexto', 'Text', comum.textoSeguro(C.aviso))
    bang('!SetOption', 'AvisoTexto', 'ToolTipText', comum.textoSeguro(C.aviso))
    bang('!ShowMeter', 'AvisoTexto'); bang('!ShowMeter', 'AvisoIcone')
  else
    bang('!HideMeter', 'AvisoTexto'); bang('!HideMeter', 'AvisoIcone')
  end
end

-- alvo visual de um conteúdo
local function alvo(C)
  local p = PAPEL[C.papel]
  local btnX = ({off = 362, dim = 362, lit = 286})[C.btn]
  return {
    bg = CFG.cor[p.bg], on = CFG.cor[p.on], r = {p.r[1], p.r[2], p.r[3], p.r[4]},
    esc = 1, flash = 0, txtA = 1, txtDy = 0, btnX = btnX,
    btnA = C.btn == 'off' and 0 or 1, btnLit = C.btn == 'lit' and 1 or 0,
    amp = 3, h = C.aviso and H_AVISO or H_BASE,
    mist = C.papel == 'agora' and 0.6 or 0,
  }
end

-- desenha V (visual) com o conteúdo C
local function desenhar(C, Vv, metaMudou)
  local on, bg = Vv.on, Vv.bg
  bang('!SetOption', 'Cartao', 'Contorno', contorno(W, Vv.h, Vv.r, Vv.esc))
  bang('!SetOption', 'Cartao', 'Shape', 'Path Contorno | Fill Color ' .. bg .. ' | StrokeWidth 0')
  bang('!SetOption', 'Cartao', 'Shape2', 'Path Contorno | Fill Color ' .. anim.alfa('255,255,255', 255, Vv.flash) .. ' | StrokeWidth 0')
  local a, dy = Vv.txtA, Vv.txtDy
  bang('!SetOption', 'Kick', 'FontColor', anim.alfa(on, 219, a))
  bang('!SetOption', 'Kick', 'Y', num(sc(48 + dy)))
  bang('!SetOption', 'Titulo', 'FontColor', anim.alfa(on, 255, a))
  bang('!SetOption', 'Titulo', 'Y', num(sc(89 + dy)))
  if metaMudou then posicionarMeta(C, dy) end
  for i = 1, 4 do
    bang('!SetOption', 'Meta' .. i, 'FontColor', anim.alfa(on, 209, a))
    bang('!SetOption', 'Meta' .. i, 'Y', num(sc(C.metaY + dy)))
  end
  desenharOnda(C, on, a, dy, Vv.amp)
  -- botão: pílula de btnX até 406; cor = on a 14 % (apagado) até on cheio (aceso)
  if Vv.btnA > 0.01 then
    local fill = anim.cor(anim.alfa(on, 36, 1), anim.alfa(on, 255, 1), Vv.btnLit)
    fill = anim.alfa(fill, tonumber(fill:match('(%d+)$')), Vv.btnA)
    local esc = 0.6 + 0.4 * Vv.btnA
    local bw, bh = (406 - Vv.btnX) * esc, 44 * esc
    local bx, by = 406 - bw, 48 - bh / 2
    -- o meter fica na posição da pílula e a forma em coordenadas locais: o retângulo do meter é a
    -- área do ToolTipText (com X=0,Y=0 o tooltip do botão cobriria o rótulo e o título). A máscara
    -- (BotaoMasc) continua em 0,0: o BotaoRotulo é posicionado relativo a ela.
    bang('!SetOption', 'Botao', 'X', num(sc(bx)))
    bang('!SetOption', 'Botao', 'Y', num(sc(by)))
    bang('!SetOption', 'Botao', 'Shape', string.format('Rectangle 0,0,%s,%s,%s | Fill Color %s | StrokeWidth 0',
      num(sc(bw)), num(sc(bh)), num(sc(bh / 2)), fill))
    bang('!SetOption', 'BotaoMasc', 'Shape', string.format('Rectangle %s,%s,%s,%s,%s | Fill Color 255,255,255,255 | StrokeWidth 0',
      num(sc(bx)), num(sc(by)), num(sc(bw)), num(sc(bh)), num(sc(bh / 2))))
    local fg = anim.cor(on, bg, Vv.btnLit)
    bang('!SetOption', 'BotaoIcone', 'FontColor', anim.alfa(fg, 255, Vv.btnA))
    local rot = anim.limitar((362 - Vv.btnX) / 76, 0, 1)
    bang('!SetOption', 'BotaoRotulo', 'FontColor', anim.alfa(fg, 255, rot * Vv.btnA))
    bang('!ShowMeter', 'Botao'); bang('!ShowMeter', 'BotaoIcone'); bang('!ShowMeter', 'BotaoRotulo')
  else
    bang('!HideMeter', 'Botao'); bang('!HideMeter', 'BotaoIcone'); bang('!HideMeter', 'BotaoRotulo')
  end
  bang('!SetOption', 'AvisoIcone', 'FontColor', anim.alfa(on, 209, 1))
  bang('!SetOption', 'AvisoTexto', 'FontColor', anim.alfa(on, 209, 1))
  desenharLinha(C, on, 1, Vv.mist)
  bang('!UpdateMeter', '*')
  bang('!Redraw')
end

-- ---------------------------------------------------------------- transição
local function copiar(t)
  local o = {}
  for k, v in pairs(t) do
    if type(v) == 'table' then o[k] = {v[1], v[2], v[3], v[4]} else o[k] = v end
  end
  return o
end

-- quadro da transição A no instante s
local function quadro(s)
  local de, para = A.de, A.para
  local Vv = copiar(para)
  local pc = anim.saida(s / T_COR)
  Vv.bg = anim.cor(de.bg, para.bg, pc)
  Vv.on = anim.cor(de.on, para.on, pc)
  Vv.mist = (de.mist or 0) + (para.mist - (de.mist or 0)) * pc
  local pf = anim.valor(mForma, s)
  for i = 1, 4 do Vv.r[i] = de.r[i] + (para.r[i] - de.r[i]) * pf end
  Vv.h = de.h + (para.h - de.h) * pf
  if A.trocouPapel then Vv.esc = 0.965 + 0.035 * anim.valor(mBoing, s) else Vv.esc = 1 end
  local pb = anim.valor(mBoing, s)
  Vv.btnX = de.btnX + (para.btnX - de.btnX) * pb
  Vv.btnLit = de.btnLit + (para.btnLit - de.btnLit) * anim.saida(s / 0.3)
  Vv.btnA = de.btnA + (para.btnA - de.btnA) * anim.saida(s / 0.2)
  -- acendimento (uma vez, ao entrar em AGORA): sobe em 100 ms e se apaga até 450 ms
  if A.acender then
    local f = s < T_FLASH and s / T_FLASH or math.max(0, 1 - (s - T_FLASH) / (T_COR - T_FLASH))
    Vv.flash = 0.22 * f * f
  else
    Vv.flash = 0
  end
  -- texto: o antigo sai subindo 8 px; o novo entra de 18 px abaixo
  local C, metaMudou
  local sai = A.soEntrada and 0 or T_SAI
  if A.textoFixo then
    Vv.txtA, Vv.txtDy = 1, 0
    C = A.novo
  elseif s < sai then
    local q = s / sai
    Vv.txtA, Vv.txtDy = 1 - q * q, -8 * q * q
    C = A.velho
  else
    if not A.trocouTexto then
      A.trocouTexto = true
      aplicarTextos(A.novo)
      metaMudou = true
    end
    local e = anim.valor(mEsp, s - sai)
    Vv.txtA, Vv.txtDy = math.min(1, e * 1.5), 18 * (1 - e)
    C = A.novo
  end
  if A.novo.onda and not (A.velho and A.velho.onda) then
    Vv.amp = 3 * anim.valor(mBoing, s - sai)
  end
  -- durante a saída, a linha do dia já mostra o estado novo (ela não troca de texto)
  C.ag = A.novo.ag
  desenhar(C, Vv, metaMudou)
  V = Vv
end

local function terminar()
  if not A then return end
  local C = A.novo
  if not A.trocouTexto then aplicarTextos(C) end
  V = copiar(A.para)
  A = nil
  bang('!CommandMeasure', 'mAT', 'Stop 1')
  desenhar(C, V, true)
end

local function transicao(velho, novo, opcoes)
  opcoes = opcoes or {}
  if A then terminar() end
  local para = alvo(novo)
  A = {
    de = V and copiar(V) or copiar(para), para = para, velho = velho, novo = novo,
    trocouPapel = velho and velho.papel ~= novo.papel or false,
    acender = (novo.papel == 'agora') and not (velho and velho.papel == 'agora') and not opcoes.entrada,
    soEntrada = opcoes.entrada or velho == nil,
    dur = T_COR,
  }
  if A.soEntrada then A.de.txtA, A.de.txtDy = 0, 18 end
  E = novo
  return A
end

local function animar(velho, novo, opcoes)
  transicao(velho, novo, opcoes)
  if not animando() then terminar(); return end
  A.t0 = os.clock()
  quadro(0)
  bang('!CommandMeasure', 'mAT', 'Execute 1')
end

-- ---------------------------------------------------------------- ciclo
local function igualMeta(a, b)
  for i = 1, 4 do if (a.meta[i] or '') ~= (b.meta[i] or '') then return false end end
  return a.metaY == b.metaY
end

-- recalcula; anima se a chave mudou, senão só redesenha o que mudou (sem animação)
local function checar(forcarDesenho)
  local ag = agora()
  local novo = calcular(ag)
  if not E or not V then
    animar(nil, novo, {entrada = true})
    return
  end
  if novo.chave ~= E.chave then
    animar(E, novo)
    return
  end
  local metaMudou = not igualMeta(novo, E)
  if forcarDesenho or metaMudou or novo.kick ~= E.kick or novo.titulo ~= E.titulo or novo.btn ~= E.btn
    or novo.aviso ~= E.aviso or math.floor(ag / 60) ~= math.floor(E.ag / 60) then
    if novo.btn ~= E.btn then
      -- Entrar acendeu (10 min antes): transição só do botão, mesmo papel
      E = novo
      aplicarTextos(novo)
      local para = alvo(novo)
      A = {de = copiar(V), para = para, velho = novo, novo = novo, trocouPapel = false, acender = false,
           soEntrada = false, trocouTexto = true, textoFixo = true, dur = T_COR}
      if not animando() then terminar(); return end
      A.t0 = os.clock()
      bang('!CommandMeasure', 'mAT', 'Execute 1')
      return
    end
    aplicarTextos(novo)
    E = novo
    V = alvo(novo)
    desenhar(novo, V, metaMudou or forcarDesenho)
  end
end

local function lerAgenda(forcar)
  S.leitorAg.caminho = comum.caminhoAgenda()   -- !SetVariable DebugAgenda vale sem refresh
  local erroAntes = S.leitorAg.erro
  local d, mudou = S.leitorAg:ler(forcar)
  if d and mudou then
    S.dados = d
    S.animSistema = not (type(d.ambiente) == 'table' and d.ambiente.animacoes == false)
    comum.log('info', 'agenda lida: ' .. tostring(type(d.events) == 'table' and #d.events or 0) .. ' eventos')
  end
  return mudou or (S.leitorAg.erro ~= erroAntes)
end

local function lerSnapshot(forcar)
  S.leitorSnap.caminho = comum.caminhoSnapshot()
  local d, mudou = S.leitorSnap:ler(forcar)
  if d and mudou then S.snap = d end
  return mudou
end

local function seguro(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    if comum then comum.log('erro', err) else print('Horizonte Dia: ' .. tostring(err)) end
  end
end

function Initialize()
  seguro(function()
    local carregar = dofile(SKIN:GetVariable('@') .. 'Lua\\carregar.lua')
    comum = carregar('comum')
    anim = carregar('anim')
    comum.iniciar('Dia')
    mForma = anim.nomeada('forma', 0.01)
    mBoing = anim.nomeada('boing', 0.01)
    mEsp = anim.nomeada('espacial', 0.01)
    CFG.scale = tonumber(var('Scale', '1')) or 1
    CFG.livreMin = tonumber(var('LivreMin', '120')) or 120
    CFG.emMin = tonumber(var('EmMin', '60')) or 60
    CFG.urgenteMin = tonumber(var('UrgenteMin', '15')) or 15
    CFG.acendeMin = tonumber(var('AcendeMin', '10')) or 10
    CFG.linhaDe = tonumber(var('LinhaDe', '7')) or 7
    CFG.linhaAte = tonumber(var('LinhaAte', '21')) or 21
    CFG.releitura = tonumber(var('ReleituraS', '60')) or 60
    CFG.releituraSnap = tonumber(var('ReleituraSnapS', '60')) or 60
    CFG.cor = {}
    for _, k in ipairs({'CorSHi', 'CorOn', 'CorOnV', 'CorSold', 'CorOnSold', 'CorSol', 'CorOnSol', 'CorCalm',
      'CorOnCalm', 'CorAgPes', 'CorAgCor', 'CorAgFer'}) do
      CFG.cor[k] = var(k, '128,128,128')
    end
    S.animVar = var('Animacoes', '1') ~= '0'
    S.privado = var('Privado', '0') == '1'
    S.forcada = hhmmParaSeg(var('DebugHora', ''))
    S.leitorAg = comum.leitor(comum.caminhoAgenda(), {schemaVersion = 1})
    S.leitorSnap = comum.leitor(comum.caminhoSnapshot())
    lerAgenda(true)
    lerSnapshot(true)
  end)
end

function Update()
  if not comum then return '' end
  seguro(function()
    if not S.pronto then
      S.pronto = true
      checar()
      return
    end
    S.seg, S.segSnap = S.seg + 1, S.segSnap + 1
    local mudou = false
    if S.seg >= CFG.releitura then S.seg = 0; mudou = lerAgenda(false) or mudou end
    if S.segSnap >= CFG.releituraSnap then S.segSnap = 0; mudou = lerSnapshot(false) or mudou end
    if A then return end
    local m = math.floor(agora() / 60)
    if mudou or m ~= S.minuto then
      S.minuto = m
      checar(mudou)
    end
  end)
  return E and E.papel or ''
end

-- Passo do ActionTimer (~16 ms pedidos; o tempo real vem de os.clock)
function Passo()
  seguro(function()
    if not A or not A.t0 then
      bang('!CommandMeasure', 'mAT', 'Stop 1')
      return
    end
    local s = os.clock() - A.t0
    if s >= A.dur then terminar() else quadro(s) end
  end)
end

-- Chamado pelo agenda_sync depois de gravar o agenda.json
function Recarregar()
  seguro(function()
    lerAgenda(true)
    lerSnapshot(true)
    if S.pronto and not A then checar(true) end
  end)
end

-- Modo privado: a Agenda chama Privado(0|1) depois de gravar Privado no Local.inc (cadeado).
function Privado(v)
  seguro(function()
    S.privado = tostring(v) == '1'
    if S.pronto and not A then checar(true) end
  end)
end

-- Repete a entrada (menu de contexto)
function Entrada()
  seguro(function()
    if A then terminar() end
    E = nil
    checar()
  end)
end

-- Depuração: esquece o último estado bom (agenda e snapshot) e relê, como num widget recém-carregado.
-- Serve para provar "arquivo ausente desde o início" sem !Refresh (que zera o DebugAgenda).
function Esquecer()
  seguro(function()
    S.dados, S.snap = nil, nil
    S.leitorAg = comum.leitor(comum.caminhoAgenda(), {schemaVersion = 1})
    S.leitorSnap = comum.leitor(comum.caminhoSnapshot())
    lerAgenda(true)
    lerSnapshot(true)
    if A then terminar() end
    checar(true)
  end)
end

-- Depuração: congela a hora ('14:37') e anima a troca; '' volta à hora real.
function Forcar(hhmm)
  seguro(function()
    S.forcada = hhmmParaSeg(hhmm)
    if A then terminar() end
    S.minuto = math.floor(agora() / 60)
    checar(true)
  end)
end

-- Depuração: desenha um quadro PARADO da transição de 'de' para 'para' na fração p (0..1) de 450 ms.
-- A hora fica congelada em 'para' até Forcar('').
function Quadro(de, para, p)
  seguro(function()
    if A then terminar() end
    S.forcada = hhmmParaSeg(de)
    E, V = nil, nil
    local velho = calcular(agora())
    E, V = velho, alvo(velho)
    aplicarTextos(velho)
    desenhar(velho, V, true)
    S.forcada = hhmmParaSeg(para)
    S.minuto = math.floor(agora() / 60)
    transicao(velho, calcular(agora()))
    quadro(tonumber(p) * T_COR)
    A = nil
  end)
end
