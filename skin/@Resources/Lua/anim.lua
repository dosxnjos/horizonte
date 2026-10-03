-- Horizonte: molas pré-calculadas e easing para as transições curtas dos widgets.
-- Arquivo em UTF-16 LE com BOM; carregado por carregar.lua.
--
-- Regra do pacote: nada de animação em laço. Uma transição (≤ 500 ms) é disparada por mudança de
-- estado/valor, roda por ActionTimer e para sozinha. O tempo vem de os.clock(), que no Windows é
-- tempo de parede desde o início do processo (spike S7: 16,8 s de os.clock em 16 s de parede com
-- ~9 % de CPU), então a curva não depende de quantos quadros o Rainmeter conseguiu desenhar.
--
-- A física é a mesma do protótipo (design/horizonte-v1-expressivo.html, classe Spring): massa 1,
-- rigidez k, amortecimento z (1 = crítico, sem overshoot). Integração semi-implícita a 240 Hz,
-- tabela amostrada a cada 1/240 s e normalizada para ir de 0 a 1.

local M = {}

local H = 1 / 240

-- Constrói a tabela de uma mola que sai de 0 e vai a 1.
-- Retorna {k, z, dur (s), n, v = {x0, x1, ...}}. eps: tolerância de repouso.
function M.mola(k, z, eps)
  eps = eps or 0.002
  local c = 2 * z * math.sqrt(k)
  local x, v = 0, 0
  local t = {0}
  local n = 1
  for _ = 1, 240 * 3 do
    local a = -k * (x - 1) - c * v
    v = v + a * H
    x = x + v * H
    n = n + 1
    t[n] = x
    if math.abs(x - 1) < eps and math.abs(v) < eps * 20 then break end
  end
  t[n] = 1
  return {k = k, z = z, dur = (n - 1) * H, n = n, v = t}
end

-- Valor da mola no instante s (segundos desde o início). Antes de 0 dá 0, depois do fim dá 1.
function M.valor(m, s)
  if s <= 0 then return 0 end
  if s >= m.dur then return 1 end
  local f = s / H
  local i = math.floor(f)
  local r = f - i
  local a, b = m.v[i + 1], m.v[i + 2] or 1
  return a + (b - a) * r
end

-- Valor da mola por fração da duração (0..1), útil para quadros congelados de depuração.
function M.valorFracao(m, p) return M.valor(m, p * m.dur) end

-- Molas nomeadas do protótipo (CFG). 'rolagem' é a do relógio: crítica (sem overshoot), ~350 ms.
M.CFG = {
  rolagem = {k = 560, z = 1},
  rapida = {k = 800, z = 0.6},
  espacial = {k = 380, z = 0.8},
  lenta = {k = 200, z = 0.8},
  boing = {k = 520, z = 0.45},
  forma = {k = 420, z = 0.55},
  entrada = {k = 240, z = 0.68},
  dado = {k = 260, z = 1},
  agulha = {k = 420, z = 0.62},
  -- linha da lista da Agenda (entrada escalonada): mesma mola do protótipo (CFG.row)
  row = {k = 420, z = 0.72},
}

-- eps opcional: tolerância de repouso. 0.01 corta a cauda invisível das molas que passam do ponto
-- (forma e boing: ~0,42 s em vez de ~0,55 s), para caber no teto de 500 ms por transição.
local cache = {}
function M.nomeada(nome, eps)
  local chave = nome .. '|' .. tostring(eps or '')
  if not cache[chave] then
    local c = M.CFG[nome]
    cache[chave] = M.mola(c.k, c.z, eps)
  end
  return cache[chave]
end

-- Easing clássicos (p em 0..1)
function M.limitar(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end
function M.lerp(a, b, p) return a + (b - a) * p end
function M.saida(p) p = M.limitar(p, 0, 1); return 1 - (1 - p) ^ 3 end
function M.entradaSaida(p)
  p = M.limitar(p, 0, 1)
  if p < 0.5 then return 4 * p ^ 3 end
  return 1 - (-2 * p + 2) ^ 3 / 2
end

-- Cor "R,G,B" ou "R,G,B,A" interpolada; devolve string pronta para FontColor/Fill.
local function cor(s)
  local t = {}
  for n in tostring(s):gmatch('[%d%.]+') do t[#t + 1] = tonumber(n) end
  t[4] = t[4] or 255
  return t
end
function M.cor(c1, c2, p)
  local a, b = cor(c1), cor(c2)
  local o = {}
  for i = 1, 4 do o[i] = math.floor(a[i] + (b[i] - a[i]) * p + 0.5) end
  return table.concat(o, ',')
end

-- Cor com alfa multiplicado (f em 0..1): M.alfa('0,33,27', 36, 0.5) -> "0,33,27,18"
function M.alfa(rgb, a, f)
  local t = cor(rgb)
  return string.format('%d,%d,%d,%d', t[1], t[2], t[3], math.floor((a or 255) * M.limitar(f, 0, 1) + 0.5))
end

return M
