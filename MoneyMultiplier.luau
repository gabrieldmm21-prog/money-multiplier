--[[
=================================================================================
                        README - GAMEPASS 2X MONEY
=================================================================================

O QUE ESTE SCRIPT FAZ:
Este módulo verifica se o jogador possui a gamepass "MoreCoins" (2x Money) e
retorna o multiplicador correto (2x se tiver, 1x se não tiver) para ser
aplicado sempre que o jogador ganhar dinheiro no jogo.

ONDE COLOCAR:
- Este é um ModuleScript. Coloque-o em ServerScriptService (ou dentro de uma
  pasta "Modules", como preferir organizar).

CONFIGURAÇÃO NECESSÁRIA:
1. No seu GamepassesConfig, garanta que o gamepass "MoreCoins" tenha o
   GamepassId real preenchido (hoje ele está sem ID configurado):

   Config.Gamepasses.MoreCoins = {
       Id = 123456789, -- <<< coloque o ID real da gamepass aqui
       ...
   }

2. Ajuste o nome do valor de dinheiro no leaderstats se for diferente de
   "Money" (procure pela linha marcada com [AJUSTE AQUI] mais abaixo).

COMO USAR NO SEU CÓDIGO (exemplo):
------------------------------------------------------------
local MoneyMultiplier = require(game.ServerScriptService.MoneyMultiplier)

-- Sempre que for dar dinheiro ao jogador, use AwardMoney no lugar de
-- alterar o leaderstats diretamente:
MoneyMultiplier.AwardMoney(player, 50) -- dá 50, ou 100 se tiver a gamepass
------------------------------------------------------------

Se preferir só consultar o multiplicador (sem que o script mexa no
leaderstats por você), use:
------------------------------------------------------------
local multiplicador = MoneyMultiplier.GetMultiplier(player)
local valorFinal = valorBase * multiplicador
------------------------------------------------------------

OBSERVAÇÕES IMPORTANTES:
- O resultado de UserOwnsGamePassAsync é cacheado por 60 segundos para não
  sobrecarregar a API do Roblox. Isso é o padrão recomendado pela própria
  Roblox (a documentação oficial recomenda não checar a cada uso, e sim
  cachear e/ou usar o evento PromptGamePassPurchaseFinished para atualizar
  o cache na hora da compra).
- O cache é atualizado automaticamente assim que o jogador compra a
  gamepass durante a sessão (não precisa dar Rejoin).
- Se a MarketplaceService falhar (erro de rede), o script tenta de novo
  com pcall e, em caso de falha total, assume 1x para não travar o jogo.

=================================================================================
--]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local GamepassesConfig = require(game.ServerScriptService.GamepassesConfig) -- [AJUSTE AQUI se o caminho for diferente]

local MoneyMultiplier = {}

local MULTIPLIER = 2
local CACHE_DURATION = 60 -- segundos

-- cache[userId] = { owns = bool, timestamp = os.clock() }
local ownershipCache = {}

-- overrides[userId] = true/false (usado apenas pelo simulador de testes)
local testOverrides = {}

-- Força um valor de "possui gamepass" para o jogador, ignorando o
-- MarketplaceService. Usado pelo GamepassSimulator para testar sem gastar
-- Robux de verdade. Passe nil para remover o override.
function MoneyMultiplier.SetTestOverride(player, value)
	if value == nil then
		testOverrides[player.UserId] = nil
	else
		testOverrides[player.UserId] = value
	end
end

local function checkOwnership(player)
	local passId = GamepassesConfig.Gamepasses.MoreCoins.Id

	if not passId or passId == 0 then
		warn("[MoneyMultiplier] GamepassId de MoreCoins não está configurado no GamepassesConfig!")
		return false
	end

	local success, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)

	if success then
		return owns
	else
		warn("[MoneyMultiplier] Falha ao checar gamepass para " .. player.Name .. ", assumindo 1x.")
		return false
	end
end

-- Retorna true/false se o jogador tem a gamepass, usando cache de 60s
function MoneyMultiplier.PlayerOwnsMoneyPass(player)
	if testOverrides[player.UserId] ~= nil then
		return testOverrides[player.UserId]
	end

	local cached = ownershipCache[player.UserId]

	if cached and (os.clock() - cached.timestamp) < CACHE_DURATION then
		return cached.owns
	end

	local owns = checkOwnership(player)
	ownershipCache[player.UserId] = { owns = owns, timestamp = os.clock() }

	return owns
end

-- Retorna 2 se o jogador tem a gamepass, ou 1 se não tem
function MoneyMultiplier.GetMultiplier(player)
	if MoneyMultiplier.PlayerOwnsMoneyPass(player) then
		return MULTIPLIER
	end
	return 1
end

-- Dá dinheiro ao jogador já aplicando o multiplicador automaticamente.
-- Use esta função no lugar de mexer direto no leaderstats.
function MoneyMultiplier.AwardMoney(player, baseAmount)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		warn("[MoneyMultiplier] " .. player.Name .. " não tem leaderstats.")
		return
	end

	local money = leaderstats:FindFirstChild("Money") -- [AJUSTE AQUI se o valor tiver outro nome]
	if not money then
		warn("[MoneyMultiplier] leaderstats de " .. player.Name .. " não tem o valor 'Money'.")
		return
	end

	local finalAmount = baseAmount * MoneyMultiplier.GetMultiplier(player)
	money.Value += finalAmount

	return finalAmount
end

-- Atualiza o cache assim que o jogador compra a gamepass durante a sessão
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
	if wasPurchased and gamepassId == GamepassesConfig.Gamepasses.MoreCoins.Id then
		ownershipCache[player.UserId] = { owns = true, timestamp = os.clock() }
	end
end)

-- Limpa o cache quando o jogador sai
Players.PlayerRemoving:Connect(function(player)
	ownershipCache[player.UserId] = nil
end)

return MoneyMultiplier
