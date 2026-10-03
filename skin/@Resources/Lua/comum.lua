-- Horizonte: funções comuns aos widgets (arquivo, JSON, datas em pt-BR, log).
-- Arquivo em UTF-16 LE com BOM; carregado por carregar.lua (o dofile não lê UTF-16).
-- Cada widget tem a própria instância de Lua: nada aqui é compartilhado entre widgets em memória.

local M = {}

local RES = SKIN:GetVariable('@')
M.json = dofile(RES .. 'Lua\\json.lua')

M.widget = '?'
M.debug = false

-- ---------------------------------------------------------------- caminhos e log

local DADOS = (os.getenv('LOCALAPPDATA') or '') .. '\\Horizonte\\'

function M.caminhoDados(nome) return DADOS .. nome end

-- Caminho do agenda.json. DebugAgenda (variável) troca por um arquivo de teste, para provar
-- estados (sem feriado, feriado hoje, JSON quebrado) sem mexer no arquivo real.
function M.caminhoAgenda()
  local dbg = SKIN:GetVariable('DebugAgenda', '')
  if dbg and dbg ~= '' then return dbg end
  return DADOS .. 'agenda.json'
end

local LOG = DADOS .. 'widget.log'
local LOG_MAX = 256 * 1024

-- Grava uma linha em %LOCALAPPDATA%\Horizonte\widget.log. nivel: 'erro' sempre grava;
-- 'info' só com DebugLog=1. Nunca grave título de evento nem e-mail aqui.
function M.log(nivel, msg)
  if nivel ~= 'erro' and not M.debug then return end
  local modo = 'a'
  local f0 = io.open(LOG, 'rb')
  if f0 then
    local tam = f0:seek('end')
    f0:close()
    if tam and tam > LOG_MAX then modo = 'w' end
  end
  local f = io.open(LOG, modo)
  if not f then return end
  f:write(os.date('%Y-%m-%d %H:%M:%S'), ' ', M.widget, ' ', nivel, ' ', tostring(msg), '\n')
  f:close()
  if nivel == 'erro' then print('Horizonte ' .. M.widget .. ': ' .. tostring(msg)) end
end

function M.iniciar(widget)
  M.widget = widget
  M.debug = tonumber(SKIN:GetVariable('DebugLog', '0')) == 1
end

-- ---------------------------------------------------------------- arquivo e JSON

function M.lerArquivo(caminho)
  local f, err = io.open(caminho, 'rb')
  if not f then return nil, err end
  local s = f:read('*a')
  f:close()
  return s
end

function M.tirarBom(s)
  if s and s:sub(1, 3) == '\239\187\191' then return s:sub(4) end
  return s
end

-- Leitor de um JSON com cache do último estado bom.
--   local l = comum.leitor(caminho, {schemaVersion = 1})
--   local dados, mudou = l:ler()   -- dados = último estado bom (ou nil se nunca leu)
-- Só decodifica quando o conteúdo do arquivo mudou (comparação do texto cru: o Lua não tem
-- mtime). Arquivo ausente, pela metade ou de outra versão: mantém o último estado bom.
function M.leitor(caminho, opcoes)
  opcoes = opcoes or {}
  local L = {caminho = caminho, cru = nil, dados = nil, erro = nil}
  function L:ler(forcar)
    local cru, err = M.lerArquivo(self.caminho)
    if not cru then
      self.erro = 'sem arquivo'
      if forcar then M.log('info', 'leitor: arquivo ausente (' .. tostring(err and 'io' or '?') .. ')') end
      return self.dados, false
    end
    if cru == self.cru and not forcar then return self.dados, false end
    -- o mesmo conteúdo ruim da última vez (arquivo ainda quebrado ou de outra versão): não decodifica
    -- nem loga de novo a cada releitura; o erro daquele conteúdo continua valendo
    if cru == self.cruRuim and not forcar then
      self.erro = self.erroRuim
      return self.dados, false
    end
    local ok, d = pcall(M.json.decode, M.tirarBom(cru))
    if not ok or type(d) ~= 'table' then
      self.erro, self.cruRuim = 'json inválido', cru
      self.erroRuim = self.erro
      M.log('erro', 'leitor: JSON inválido, mantendo o último estado bom')
      return self.dados, false
    end
    if opcoes.schemaVersion and d.schemaVersion ~= opcoes.schemaVersion then
      self.erro, self.cruRuim = 'schemaVersion ' .. tostring(d.schemaVersion), cru
      self.erroRuim = self.erro
      M.log('erro', 'leitor: schemaVersion ' .. tostring(d.schemaVersion) .. ' não suportada')
      return self.dados, false
    end
    local mudou = (cru ~= self.cru)
    self.cru, self.dados, self.erro, self.cruRuim = cru, d, nil, nil
    return d, mudou or forcar
  end
  return L
end

-- ---------------------------------------------------------------- datas em pt-BR

-- os.date('%A') sai em inglês no Rainmeter: nomes por tabela. Índice = wday do Lua (1 = domingo).
M.DIAS = {'domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'}
M.DIAS_CURTOS = {'dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'}
M.MESES = {'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto',
  'setembro', 'outubro', 'novembro', 'dezembro'}

-- "sexta, 2 de outubro"
function M.dataExtensa(t)
  local d = os.date('*t', t)
  return M.DIAS[d.wday] .. ', ' .. d.day .. ' de ' .. M.MESES[d.month]
end

-- "14:37" (24 h, com zero à esquerda)
function M.hhmm(t) return os.date('%H:%M', t) end

-- "2026-10-02" no fuso local
function M.dataIso(t) return os.date('%Y-%m-%d', t) end

-- "2026-10-12" -> epoch do meio-dia local daquele dia (meio-dia: imune a horário de verão)
function M.epochDeData(iso)
  local a, m, d = tostring(iso or ''):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
  if not a then return nil end
  return os.time({year = tonumber(a), month = tonumber(m), day = tonumber(d), hour = 12})
end

-- "seg 12/10"
function M.diaCurtoData(iso)
  local t = M.epochDeData(iso)
  if not t then return nil end
  local d = os.date('*t', t)
  return string.format('%s %02d/%02d', M.DIAS_CURTOS[d.wday], d.day, d.month)
end

-- Texto do chip de feriado a partir de agenda.json.proximoFeriado.
-- nil quando não há feriado ou quando a data já passou (arquivo velho).
function M.rotuloFeriado(pf, hojeIso)
  if type(pf) ~= 'table' or type(pf.data) ~= 'string' then return nil end
  if not M.epochDeData(pf.data) then return nil end
  if pf.data < hojeIso then return nil end
  if pf.data == hojeIso then return 'feriado hoje' end
  return 'feriado ' .. M.diaCurtoData(pf.data)
end

-- ---------------------------------------------------------------- tempo e dados (Dia, Claude)

-- Meia-noite local do dia de t (epoch). os.time normaliza dia 32 etc., então +N dias é seguro.
function M.inicioDoDia(t, deslocDias)
  local d = os.date('*t', t)
  return os.time({year = d.year, month = d.month, day = d.day + (deslocDias or 0), hour = 0, min = 0, sec = 0})
end

-- Duração em minutos, como no protótipo: "23 min", "2h", "1h30"
function M.duracao(min)
  min = math.max(0, math.floor(min + 0.5))
  if min < 60 then return min .. ' min' end
  local h, r = math.floor(min / 60), min % 60
  if r == 0 then return h .. 'h' end
  return string.format('%dh%02d', h, r)
end

-- Segundos que o fuso local está à frente do UTC (Brasil: -10800), no instante t.
local function deslocLocal(t)
  local u = os.date('!*t', t)
  u.isdst = false
  return os.difftime(t, os.time(u))
end

-- ISO 8601 com fuso ("2026-10-03T00:19:59.775380+00:00", "...Z", "...-03:00") -> epoch UTC (s).
-- nil se não casar. Fração de segundo é descartada. Sem fuso: tratado como UTC.
function M.epochIso(s)
  if type(s) ~= 'string' then return nil end
  local a, mo, d, h, mi, se, resto = s:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):(%d%d)(.*)$')
  if not a then return nil end
  resto = resto:gsub('^%.%d+', '')
  local off = 0
  if resto ~= 'Z' and resto ~= '' then
    local sinal, oh, om = resto:match('^([%+%-])(%d%d):?(%d%d)$')
    if not sinal then return nil end
    off = (tonumber(oh) * 3600 + tonumber(om) * 60) * (sinal == '-' and -1 or 1)
  end
  -- os.time lê a tabela como hora LOCAL: compensa o fuso local para chegar ao instante UTC
  local t = os.time({year = tonumber(a), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = tonumber(se), isdst = false})
  if not t then return nil end
  return t + deslocLocal(t) - off
end

-- "#7AA2F7" -> "122,162,247" (nil se não for hex de 6 dígitos)
function M.corHex(hex)
  local r, g, b = tostring(hex or ''):match('^#?(%x%x)(%x%x)(%x%x)$')
  if not r then return nil end
  return tonumber(r, 16) .. ',' .. tonumber(g, 16) .. ',' .. tonumber(b, 16)
end

-- Caminho do snapshot.json do claude-usage-tray. Só leitura: nunca uma segunda coleta.
-- DebugSnapshot (variável) troca por um arquivo de teste.
function M.caminhoSnapshot()
  local dbg = SKIN:GetVariable('DebugSnapshot', '')
  if dbg and dbg ~= '' then return dbg end
  return (os.getenv('LOCALAPPDATA') or '') .. '\\claude-usage-tray\\snapshot.json'
end

-- "%USERPROFILE%\x" -> caminho com as variáveis de ambiente expandidas (as desconhecidas ficam como
-- estão). Caminho de variável do skin nunca leva o nome de usuário escrito: leva %VAR%.
function M.expandirAmbiente(s)
  return (tostring(s or ''):gsub('%%([%w_%(%)]+)%%', function(n) return os.getenv(n) or ('%' .. n .. '%') end))
end

-- true se o arquivo existe e abre para leitura
function M.existe(caminho)
  local f = io.open(tostring(caminho or ''), 'rb')
  if not f then return false end
  f:close()
  return true
end

-- URL que pode virar ação de clique: só http(s), sem espaço, aspas, colchetes nem '#' (o Rainmeter
-- leria [ ] como bang e #x# como variável). nil se não servir.
function M.urlSegura(u)
  if type(u) ~= 'string' then return nil end
  if not u:match('^https?://') then return nil end
  if u:find('[%s"%[%]#`<>]') then return nil end
  return u
end

-- ---------------------------------------------------------------- utilidades de meter

function M.num(x) return string.format('%.2f', x) end

-- Escapa texto para !SetOption (aspas duplas viram aspas tipográficas; o Rainmeter não tem escape).
function M.textoSeguro(s)
  return (tostring(s or ''):gsub('"', '\226\128\157'))
end

return M
