-- Horizonte: geometria e desenho de anel no gesto do protótipo (Ring de design/horizonte-v1-expressivo.html):
-- viewBox 128, raio 50, ponta redonda, folga de 4 px entre o indicador e o trilho, disco interno que vira
-- "cookie"/"sol" (forma polar de N lóbulos) e, opcional, um ponto marcador acima do topo do anel.
-- Arquivo em UTF-16 LE com BOM; carregado por carregar.lua. Só gera as strings de Shape: quem chama faz o
-- !SetOption no meter. Usado pelo Claude; o Maquina.lua ainda tem a cópia original destas funções
-- (migração pendente, docs/widgets.md § Claude).
--
--   local anel = carregar('anel')
--   local A = anel.novo(136, 9, sc)           -- px do anel, traço em unidades do viewBox, Scale
--   A:disco('48,164,108,38', 0.1, 18)          -- devolve shape, caminho (nil = círculo)
--   A:arcos(0.4, trilho, indicador, 8)         -- devolve Shape2 (trilho) e Shape3 (indicador)
--   A:ponto('229,72,77', 1)                    -- Shape do ponto marcador (escala 0..1+)

local M = {}

M.VAZIO = 'Rectangle 0,0,0,0 | StrokeWidth 0 | Fill Color 0,0,0,0'

local function num(x) return string.format('%.2f', x) end
M.num = num

local Anel = {}
Anel.__index = Anel

-- px: diâmetro do anel na tela (lógico); sw: traço no viewBox 128; sc: Scale.
-- opcoes.lobulos (10), opcoes.folgaDisco (7, no viewBox), opcoes.vaoPx (4).
function M.novo(px, sw, sc, opcoes)
  opcoes = opcoes or {}
  sc = sc or 1
  local k = px / 128 * sc
  local o = setmetatable({}, Anel)
  o.k = k
  o.c = 64 * k
  o.r = 50 * k
  o.sw = sw * k
  o.R = (50 - sw / 2 - (opcoes.folgaDisco or 7)) * k
  o.lobulos = opcoes.lobulos or 10
  -- folga entre as pontas redondas do indicador e do trilho, em graus (mesma conta do protótipo: gapU)
  o.vaoGraus = (sw + (opcoes.vaoPx or 4) * 128 / px) / (2 * math.pi * 50) * 360
  -- ponto marcador: no protótipo, cy = 64 - r - sw/2 - 5 e raio 3,6 (viewBox)
  o.pcx = 64 * k
  o.pcy = (64 - 50 - sw / 2 - 5) * k
  o.pr = 3.6 * k
  return o
end

function Anel:xy(graus, raio)
  local th = math.rad(graus)
  return self.c + raio * math.sin(th), self.c - raio * math.cos(th)
end

-- Arco no sentido horário a partir de 12 h (graus a0..a1).
function Anel:arco(a0, a1, cor)
  local x0, y0 = self:xy(a0, self.r)
  local x1, y1 = self:xy(a1, self.r)
  return string.format('Arc %s,%s,%s,%s,%s,%s,0,0,%d | StrokeWidth %s | Stroke Color %s | '
    .. 'StrokeStartCap Round | StrokeEndCap Round | Fill Color 0,0,0,0',
    num(x0), num(y0), num(x1), num(y1), num(self.r), num(self.r), (a1 - a0) > 180 and 1 or 0, num(self.sw), cor)
end

function Anel:circulo(cor)
  return string.format('Ellipse %s,%s,%s | StrokeWidth %s | Stroke Color %s | Fill Color 0,0,0,0',
    num(self.c), num(self.c), num(self.r), num(self.sw), cor)
end

-- Disco interno. amp 0 = círculo; ~0,05 = cookie; ~0,1 = sol. rot em graus.
-- Devolve shape e, se for forma, o caminho (vai numa opção do meter, ex.: Disco=..., e o shape é
-- "Path Disco | ..."). nomeCaminho: nome dessa opção (padrão 'Disco').
function Anel:disco(cor, amp, rot, nomeCaminho)
  nomeCaminho = nomeCaminho or 'Disco'
  if math.abs(amp) < 0.002 then
    return string.format('Ellipse %s,%s,%s | Fill Color %s | StrokeWidth 0', num(self.c), num(self.c), num(self.R), cor), nil
  end
  local p, N, rr = {}, 72, math.rad(rot or 0)
  for i = 0, N do
    local th = i / N * 2 * math.pi
    local r = self.R * (1 + amp * math.cos(self.lobulos * (th - rr)))
    local x, y = self.c + r * math.sin(th), self.c - r * math.cos(th)
    p[#p + 1] = (i == 0 and '' or 'LineTo ') .. num(x) .. ',' .. num(y)
  end
  return 'Path ' .. nomeCaminho .. ' | Fill Color ' .. cor .. ' | StrokeWidth 0', table.concat(p, ' | ') .. ' | ClosePath 1'
end

-- Trilho e indicador para a fração f (0..1). minGraus: varredura mínima, inclusive em f = 0 (o tray usa
-- 8° na escala ampliada: 95 % é "início da cauda", não anel vazio). Devolve shape do trilho e do indicador.
function Anel:arcos(f, corTrilho, corInd, minGraus)
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  local a1 = f * 360
  if minGraus and a1 < minGraus then a1 = minGraus end
  if a1 < 1.44 then
    return self:circulo(corTrilho), M.VAZIO
  elseif a1 > 358.56 then
    return M.VAZIO, self:circulo(corInd)
  end
  local t0, t1 = a1 + self.vaoGraus, 360 - self.vaoGraus
  local trilho = (t1 - t0 > 1.08) and self:arco(t0, t1, corTrilho) or M.VAZIO
  return trilho, self:arco(0, a1, corInd)
end

-- Ponto marcador acima do topo, escala e (0 = some; a mola boing passa um pouco de 1).
function Anel:ponto(cor, e)
  if not e or e < 0.02 then return M.VAZIO end
  return string.format('Ellipse %s,%s,%s | Fill Color %s | StrokeWidth 0', num(self.pcx), num(self.pcy), num(self.pr * e), cor)
end

return M
