-- Horizonte: demo data (Demo=1 in @Resources\Settings.inc).
-- Builds a sample agenda.json and a sample Claude snapshot.json in memory, relative to TODAY, so the
-- suite looks alive right after install, with no helper, no tray app and no network.
-- Same formats as the real files (docs/CONTRATOS.md in the GitHub repo). Nothing here is real data.
-- Loaded by comum.lua through carregar.lua. License: MIT.

local M = {}

-- epoch of today (+d days) at hh:mm, local time
local function em(d, hh, mm)
  local t = os.date('*t')
  return os.time({year = t.year, month = t.month, day = t.day + d, hour = hh, min = mm or 0, sec = 0})
end

local function dataIso(d) return os.date('%Y-%m-%d', em(d, 12)) end
local function wday(d) return os.date('*t', em(d, 12)).wday end   -- 1 = Sunday

local LINK = 'https://example.com/calendar'
local MEET = 'https://example.com/meeting'

local function ev(lista, fonte, titulo, d, h1, m1, h2, m2, extra)
  extra = extra or {}
  local e = {
    id = string.format('demo%02d%02d%02d', d + 10, h1, #lista % 100),
    source = fonte, title = titulo, allDay = false,
    start = em(d, h1, m1), ['end'] = em(d, h2, m2),
    recurring = extra.recurring or false,
    location = extra.location, meetUrl = extra.meet and MEET or nil, link = LINK,
  }
  lista[#lista + 1] = e
end

local function diaTodo(lista, fonte, titulo, d, dias, recorrente)
  lista[#lista + 1] = {
    id = string.format('demo%02d00%02d', d + 10, #lista % 100),
    source = fonte, title = titulo, allDay = true,
    startDate = dataIso(d), endDate = dataIso(d + (dias or 1)),
    recurring = recorrente or false, link = LINK,
  }
end

-- sample titles in both languages (Idioma)
local TITULOS = {
  daily = {'Daily do time', 'Team stand-up'},
  design = {'Revisão de design', 'Design review'},
  almoco = {'Almoço', 'Lunch'},
  foco = {'Foco: relatório do mês', 'Focus: monthly report'},
  um1 = {'1:1 semanal', 'Weekly 1:1'},
  dentista = {'Dentista', 'Dentist'},
  academia = {'Academia', 'Gym'},
  aniversario = {'Aniversário', 'Birthday'},
  sprint = {'Planejamento do sprint', 'Sprint planning'},
  comite = {'Comitê semanal', 'Weekly sync'},
  cinema = {'Cinema', 'Movie night'},
  feriado = {'Feriado (exemplo)', 'Holiday (sample)'},
  viagem = {'Viagem', 'Trip'},
  mercado = {'Mercado', 'Groceries'},
  local_ = {'Centro', 'Downtown'},
}
local L = 1

function M.agenda(comum)
  L = (comum and comum.en) and 2 or 1
  local function t(k) return TITULOS[k][L] end
  local E = {}
  -- a daily stand-up on weekdays (the Agenda collapses it into one "seg a sex" line)
  for d = -1, 15 do
    local w = wday(d)
    if w >= 2 and w <= 6 then ev(E, 'corporativo', t('daily'), d, 9, 0, 9, 15, {recurring = true, meet = true}) end
  end
  -- today
  ev(E, 'corporativo', t('design'), 0, 10, 0, 11, 0, {meet = true})
  ev(E, 'pessoal', t('almoco'), 0, 12, 30, 13, 30)
  ev(E, 'corporativo', t('foco'), 0, 13, 30, 14, 30)
  ev(E, 'corporativo', t('um1'), 0, 15, 0, 15, 30, {recurring = true, meet = true})
  ev(E, 'corporativo', t('um1'), 7, 15, 0, 15, 30, {recurring = true, meet = true})
  ev(E, 'pessoal', t('dentista'), 0, 17, 30, 18, 30, {location = t('local_')})
  for _, d in ipairs({0, 2, 4, 7, 9, 11}) do
    ev(E, 'pessoal', t('academia'), d, 19, 0, 20, 0, {recurring = true})
  end
  -- the next days
  diaTodo(E, 'pessoal', t('aniversario'), 1, 1, true)
  ev(E, 'corporativo', t('sprint'), 1, 10, 0, 11, 30, {meet = true})
  ev(E, 'corporativo', t('comite'), 2, 11, 0, 12, 0, {recurring = true, meet = true})
  ev(E, 'corporativo', t('comite'), 9, 11, 0, 12, 0, {recurring = true, meet = true})
  ev(E, 'pessoal', t('cinema'), 3, 20, 0, 22, 0)
  diaTodo(E, 'feriados', t('feriado'), 5, 1, false)
  diaTodo(E, 'pessoal', t('viagem'), 8, 2, false)
  ev(E, 'pessoal', t('mercado'), 6, 10, 0, 11, 0)

  -- sort by start; all-day counts from local midnight and comes first on a tie
  local function ini(e)
    if e.allDay then
      local a, m, d = e.startDate:match('^(%d+)%-(%d+)%-(%d+)$')
      return os.time({year = tonumber(a), month = tonumber(m), day = tonumber(d), hour = 0}) - 0.5
    end
    return e.start
  end
  table.sort(E, function(a, b)
    if ini(a) ~= ini(b) then return ini(a) < ini(b) end
    return a.id < b.id
  end)

  local agora = em(0, 0)
  local function fonte(id, nome, cor)
    return {id = id, nome = nome, cor = cor, status = 'ok', httpStatus = 200, lastOkAt = agora, lastAttemptAt = agora}
  end
  return {
    schemaVersion = 1,
    producer = 'Horizonte demo',
    generatedAt = agora,
    janela = {de = dataIso(-1), ate = dataIso(15)},
    ambiente = {animacoes = true},
    proximoFeriado = {data = dataIso(5), nome = t('feriado')},
    sources = {
      fonte('pessoal', 'Pessoal', '#FFA9C5'),
      fonte('corporativo', 'Corporativo', '#8ED0FF'),
      fonte('feriados', 'Feriados', '#EBCB6A'),
    },
    events = E,
  }
end

local function isoUtc(t) return os.date('!%Y-%m-%dT%H:%M:%SZ', t) end

function M.snapshot(comum)
  local agora = comum.agora()
  local min = agora - agora % 60
  -- the 5-hour window renews at the next hh:59 after 2 h; the weekly one in 3 days
  local h = os.date('*t', agora)
  local reset5h = os.time({year = h.year, month = h.month, day = h.day, hour = h.hour + 2, min = 59, sec = 0})
  local reset7d = em(3, 14, 0)
  local function barras(p5, p7)
    return {
      {Label = '5h', Pct = p5, ResetsAt = isoUtc(reset5h)},
      {Label = '7d', Pct = p7, ResetsAt = isoUtc(reset7d)},
    }
  end
  return {
    savedAt = isoUtc(min),
    accounts = {
      {Num = 1, Active = true, Status = 'ok', Stale = false, AgeS = 0, Bars = barras(42, 63)},
      {Num = 2, Active = false, Status = 'ok', Stale = false, AgeS = 0, Bars = barras(8, 27)},
    },
  }
end

-- JSON text, as if read from disk (the reader caches by text: same text = no redraw)
function M.texto(tipo, comum)
  local ok, s = pcall(function()
    return comum.json.encode(tipo == 'agenda' and M.agenda(comum) or M.snapshot(comum))
  end)
  if ok then return s end
  comum.log('erro', 'demo: ' .. tostring(s))
  return nil, 'demo'
end

return M
