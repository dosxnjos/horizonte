-- Horizonte: carregador de modulos Lua do @Resources.
--
-- Por que existe: o Rainmeter le o ScriptFile em UTF-16 LE com BOM (e so assim os acentos
-- saem certos), mas o dofile/loadfile do Lua 5.1 le bytes crus e nao entende UTF-16.
-- Este arquivo fica em ASCII puro (carregado por dofile) e carrega os outros modulos
-- aceitando UTF-16 LE com BOM, UTF-8 com BOM ou ASCII/UTF-8 sem BOM.
--
-- Uso no script do widget (dentro de Initialize):
--   local carregar = dofile(SKIN:GetVariable('@') .. 'Lua\\carregar.lua')
--   local comum = carregar('comum')   -- @Resources\Lua\comum.lua
--
-- Licenca: MIT (repositorio horizonte).

local RAIZ = SKIN:GetVariable('@') .. 'Lua\\'
local cache = {}

local function utf8_de(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
    0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

local function utf16le_para_utf8(s)
  local out, n, i = {}, 0, 1
  local len = #s - (#s % 2)
  while i < len do
    local a, b = s:byte(i, i + 1)
    local cu = a + b * 256
    i = i + 2
    if cu >= 0xD800 and cu <= 0xDBFF and i < len then
      local c, d = s:byte(i, i + 1)
      local lo = c + d * 256
      if lo >= 0xDC00 and lo <= 0xDFFF then
        cu = 0x10000 + (cu - 0xD800) * 1024 + (lo - 0xDC00)
        i = i + 2
      end
    end
    n = n + 1
    out[n] = utf8_de(cu)
  end
  return table.concat(out)
end

local function ler_fonte(caminho)
  local f, err = io.open(caminho, 'rb')
  if not f then error('carregar: nao abriu ' .. tostring(err), 0) end
  local s = f:read('*a')
  f:close()
  if s:sub(1, 2) == '\255\254' then
    return utf16le_para_utf8(s:sub(3))
  elseif s:sub(1, 3) == '\239\187\191' then
    return s:sub(4)
  end
  return s
end

-- carregar('comum') ou carregar('C:\\caminho\\x.lua'); o resultado fica em cache por nome.
return function(nome)
  if cache[nome] ~= nil then return cache[nome] end
  local caminho = nome
  if not nome:find('[\\/]') then caminho = RAIZ .. nome .. '.lua' end
  local fn, err = loadstring(ler_fonte(caminho), '=' .. nome)
  if not fn then error('carregar ' .. nome .. ': ' .. tostring(err), 0) end
  -- O Rainmeter poe SKIN no ambiente do script do widget, nao no _G: um chunk de loadstring
  -- nasce com o _G e veria SKIN = nil. O modulo herda o ambiente de quem chamou carregar().
  setfenv(fn, getfenv(2))
  local modulo = fn()
  cache[nome] = modulo
  return modulo
end
