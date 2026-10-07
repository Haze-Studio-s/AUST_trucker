import urllib.request
import urllib.error
import json

url = "http://localhost:20128/v1/chat/completions"
api_key = "sk-a3de623e55e3416c-5c7199-ff791e19"

prompt = """
Você é o Arquiteto Sênior de FiveM (QBox / ox_lib / OneSync Infinity).
Problema relatado pelo usuário:
"Após as últimas atualizações o fluxo acabou quebrando, tudo spawna porém o trabalho não inicia"

Contexto técnico no script AUST_trucker:
Ao aceitar o frete na interface NUI, o servidor executa StartTruckDelivery, que faz o spawn físico do caminhão, trailer, empilhadeira e paletes no pátio.
Porém, no client:
1. No evento 'aurp_trucker:client:polarixJobStarted':
   - Executa CleanupCurrentJob()
   - Define ActiveJob = payload e CurrentStage = 'STEP_1_START'
   - Imediatamente chama StartMissionStep1(nil, nil, nil), que define CurrentStage = 'STEP_2_ENTER_TRUCK'.
   - StartMissionStep1 chama StartTruckEnterWatcher(truck) com truck = nil.
   - StartTruckEnterWatcher fica aguardando:
     while CurrentStage == 'STEP_2_ENTER_TRUCK' and ActiveJob do
         Wait(250)
         local targetTruck = (truck and DoesEntityExist(truck)) and truck or JobEntities.truck
         if (not targetTruck or not DoesEntityExist(targetTruck)) and ActiveJob and ActiveJob.truckNetId then
             if NetworkDoesNetworkIdExist(ActiveJob.truckNetId) then
                 local resolved = NetworkGetEntityFromNetworkId(ActiveJob.truckNetId)
                 if resolved ~= 0 and DoesEntityExist(resolved) then
                     targetTruck = resolved
                     JobEntities.truck = resolved
                 end
             end
         end
         if veh ~= 0 and targetTruck and DoesEntityExist(targetTruck) and veh == targetTruck then
             local seat = GetPedInVehicleSeat(veh, -1)
             if seat == ped or seat == cache.ped then
                 OnPlayerEnteredTruck(veh)
                 break
             end
         end
     end

2. O que quebra se o jogador entrar no caminhão:
   - Se o jogador entra no caminhão, 'veh' é o handle do veículo. Mas se NetworkGetEntityFromNetworkId demorar ou se veh ~= targetTruck (por comparação de handle ou atraso no NetID), OnPlayerEnteredTruck NUNCA é chamado!
   - Falta comparar placa: se GetVehicleNumberPlateText(veh) for igual à ActiveJob.truckPlate ou se VehToNet(veh) == ActiveJob.truckNetId, deve assumir imediatamente como o caminhão da missão.
   - Além disso, no client/main.lua após o spawn, SetEntityNoCollisionEntity(truck, trailer, true) estava desativando a colisão da 5ª roda permanentemente.
   - E no client/client.lua, existem callbacks duplos e lcActiveJob local que podem sobrescrever ou cancelar o contrato.

Quais são as causas raiz e qual a solução arquitetural recomendada para o plano de ação?
Responda de forma concisa e técnica.
"""

payload = {
    "model": "auto/best-fast",
    "messages": [
        {"role": "system", "content": "Você é o Arquiteto Sênior de FiveM. Seja direto, técnico e focado na causa raiz e plano de correção."},
        {"role": "user", "content": prompt}
    ],
    "max_tokens": 1200,
    "temperature": 0.2
}

req = urllib.request.Request(
    url,
    data=json.dumps(payload).encode("utf-8"),
    headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }
)

with urllib.request.urlopen(req, timeout=30) as resp:
    data = json.loads(resp.read().decode("utf-8"))
    print("MODEL:", data.get("model"))
    print("\n--- RESPOSTA OMNIROUTE ---")
    print(data["choices"][0]["message"]["content"])
