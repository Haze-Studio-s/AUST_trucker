# AURP Trucker — Guia do Jogador

## Visão Geral

O AURP Trucker é um sistema completo de logística e transporte. Como motorista, você aceita jobs de entrega, gerencia ou participa de empresas, progride em nível e habilidades, contrata empréstimos e, se trabalhar em uma empresa de repossessão, recupera veículos inadimplentes pelo mapa.

---

## Abrindo o Menu

Interaja com o NPC no ponto de partida (AURP Logistics, próximo ao porto sul) para abrir o painel. O menu possui as abas:

| Aba | Descrição |
|---|---|
| **Jobs / Missões** | Lista de jobs disponíveis (Logística) ou ordens de repo (Repo Man) |
| **Entrega** | Acompanha o job ativo com timer e bônus |
| **Empresa** | Gerencia ou entra em uma empresa |
| **Garagem** | Veículos da empresa |
| **Indústrias** | Compra e venda de itens nas indústrias |
| **Stats** | Suas estatísticas, nível, rank e árvore de habilidades |

---

## Jobs de Entrega (Freelance)

### Como funciona
1. Abra o menu → aba **Jobs**
2. Veja os jobs disponíveis — cada card mostra: origem, destino, carga, **peso (kg)**, pagamento e tempo restante
3. Clique em um job para ver detalhes e depois em **Aceitar**
4. O GPS marca a rota até o ponto de coleta. Carregue e siga ao destino
5. Entregue no destino para receber o pagamento

### Qualquer veículo serve
Jobs podem ser feitos com **qualquer carro**. O peso da carga determina a compatibilidade:
- Carga leve (20kg) → qualquer carro
- Carga média (80kg) → Sedan, SUV, Muscle, Van ou maior
- Carga pesada (150-200kg) → Van, Utilitário, Caminhão
- Se seu veículo não suporta o peso total, a **quantidade é reduzida** automaticamente
- Motos e bicicletas **não podem** transportar carga

### Bônus de pontualidade

| Tempo | Multiplicador |
|---|---|
| Até 5 minutos | +20% |
| 5 a 10 minutos | Pagamento base |
| Mais de 10 minutos | −20% |

### Jobs expiram
Jobs com pagamento alto expiram mais rápido (mínimo 10 min). Jobs com pagamento baixo duram até 40 min. Novos jobs são gerados a cada 30 minutos.

---

## Contratos de Empresa (Tab Entrega)

### Relacionamento com Clientes
Empresas de logística podem construir **relacionamentos comerciais** com clientes (indústrias). Quanto mais entregas fizer para um cliente, melhor o relacionamento e os contratos.

### Níveis de Confiança (★)

| Nível | Nome | Bônus | Opções de Negociação |
|---|---|---|---|
| ★☆☆☆☆ | Novo | 0% | 1 opção |
| ★★☆☆☆ | Conhecido | +10% | 2 opções |
| ★★★☆☆ | Confiável | +20% | 3 opções |
| ★★★★☆ | Parceiro | +35% | 4 opções |
| ★★★★★ | Exclusivo | +50% | 5 opções |

### Como negociar um contrato
1. Menu → aba **Entrega** → lista de clientes disponíveis
2. Clique em **Negociar Contrato** no cliente desejado
3. Escolha os termos: **volume** (pacotes), **prazo** (minutos), **frequência** (entregas)
4. Opções desbloqueadas pelo nível de confiança
5. Clique em **Fechar Contrato** → contrato inicia imediatamente com GPS

### Progressão de XP
- Entrega completa: **+100 XP** base
- Streak bonus: **+10 XP** por entrega consecutiva ao mesmo cliente
- Abandono/falha: **-200 XP**, streak reseta

### Reputação por Setor
A média dos níveis de confiança com clientes do mesmo setor (Alimentos, Construção, etc.) desbloqueia **clientes premium** com pagamento superior.

### Limite de Contratos Simultâneos

| Nível da Empresa | Contratos |
|---|---|
| 1-10 | 1 |
| 11-20 | 2 |
| 21-30 | 3 |

---

## Empresas

### Tipos de empresa
Ao criar uma empresa você escolhe o tipo — isso define o que sua empresa pode fazer:

| Tipo | Função |
|---|---|
| **Logística** | Aceita jobs de entrega de carga |
| **Repo Man** | Aceita missões de repossessão de veículos |

### Criando uma empresa
- Menu → **Empresa** → preencha o nome → selecione o tipo → **Criar Empresa ($150.000)**
- O dinheiro é cobrado em cash

### Entrando em uma empresa existente
- Menu → **Empresa** → seção *Empresas Recrutando* → **Entrar**
- Só aparece empresas com recrutamento ativado

### Hierarquia
| Cargo | Permissões |
|---|---|
| **Owner** | Tudo — incluindo vender a empresa |
| **Manager** | Saque do caixa, empréstimo empresarial |
| **Worker** | Jobs e missões normais |

### Caixa da empresa
- **Depositar:** qualquer membro pode depositar cash no caixa
- **Sacar:** apenas owner e manager
- O caixa serve para pagar empréstimos empresariais e taxas do Repo Man

### Garagem
- Owner pode registrar até **2 veículos** na empresa (Menu → **Garagem** → **Registrar Veículo**)
- Membros podem **Retirar** (spawna o veículo) e **Guardar** (despawna) pela aba Garagem
- Ao retirar, o veículo aparece com **chave** e um **alvo ox_target** "Guardar Veículo" para devolver direto no mundo

### Vender a empresa
- Apenas o owner pode vender — recebe **$25.000** de volta
- Membros devem sair antes ou após a venda; owner não pode abandonar sem vender

---

## Progressão

### XP e Nível
Você ganha XP a cada entrega concluída. A fórmula é baseada no pagamento recebido e no tempo:

```
XP = max(5, floor(pagamento / 10 × multiplicador_de_tempo))
```

- **30 níveis** disponíveis (do 1 ao 30)
- A cada level-up você recebe **1 Skill Point**

### Ranks
A cada 5 níveis seu rank sobe:

| Nível | Rank |
|---|---|
| 1–5 | Aprendiz |
| 6–10 | Motorista |
| 11–15 | Veterano |
| 16–20 | Especialista |
| 21–25 | Elite |
| 26–30 | Lenda |

### Árvore de Habilidades
Acesse em Menu → **Stats** → seção *Skills*. Use Skill Points para evoluir habilidades:

| Habilidade | Ativa quando… | Efeito por nível |
|---|---|---|
| **Distance** | Job com distância ≥ 10 km | +2% no pagamento |
| **Valuable** | Pagamento base ≥ $5.000 | +2% no pagamento |
| **Fragile** | Integridade da carga ≥ 85% na entrega | +2% no pagamento |
| **Speed** | Sempre ativa | +2% no multiplicador de tempo |

**Importante:** os bônus são **contextuais** — só se aplicam quando a condição for satisfeita. Aceitar um job curto e barato não ativa Distance nem Valuable, por exemplo.

- Cada habilidade tem **6 níveis** (máx +12% por skill)
- Com todas as skills no nível máximo e condições satisfeitas: **+48% no pagamento total**
- **Speed** é o único bônus garantido em qualquer job — reduz a penalidade por entrega lenta

---

## Empréstimos

Fale com o **NPC Banqueiro** em Paleto Bay para contratar um empréstimo.

### Regras
| Parâmetro | Valor |
|---|---|
| Mínimo | $10.000 |
| Máximo | $500.000 |
| Juros | 5% |
| Parcelas | 4 semanais |
| Multa por atraso | 15% sobre o saldo devedor |

### Tipos
- **Pessoal** — para você, sem vínculo com empresa
- **Empresarial** — para o caixa da empresa (apenas owner ou manager podem contratar)

### Pagando
- Menu → **Stats** → seção *Empréstimo Pessoal*
- Ou Menu → **Empresa** → seção *Empréstimo Empresarial*
- Pague qualquer valor acima de zero a qualquer momento

### Colateral de veículo (v16)
Ao contratar um empréstimo, você pode vincular um **veículo como colateral** (apenas veículos registrados na sua empresa). Se o empréstimo ficar inadimplente, o sistema cria automaticamente uma ordem de repossessão usando o veículo vinculado.

### Consequência do atraso
Se uma parcela não for paga no prazo, o sistema aplica **multa de 15%** sobre o saldo restante. Em caso de inadimplência severa, o empréstimo gera uma **ordem de repossessão** do veículo colateral (ou de um veículo aleatório da frota, se nenhum colateral foi vinculado) — empresas Repo Man podem aceitar essa missão.

---

## Repo Man (Empresas de Repossessão)

Disponível apenas para empresas do tipo **Repo Man**.

### Como funciona
1. Menu → aba **Missões**
2. Veja as ordens disponíveis — cada card mostra o veículo, a zona no mapa, o pagamento e o tempo de expiração
3. Clique em **Aceitar Missão**
4. Um marcador aparece no mapa na zona do veículo — localize-o
5. Recupere o veículo e entregue no **depósito municipal** marcado
6. Após entregar, confirme a conclusão — o pagamento cai na sua conta

### Tipos de missão
| Tipo | Dificuldade | Multiplicador de pagamento |
|---|---|---|
| **Simples** | Fácil — veículo abandonado | ×1.0 |
| **Hostil** | Médio — NPCs armados protegendo | ×1.5 |
| **PVP** | Alto — outros jogadores podem interferir | ×2.0 |
| **Stealth** | Alto — sem alertar o dono | ×2.5 |

### Missões originadas de empréstimos (v16)
Quando um jogador deixa de pagar um empréstimo que foi vinculado a um veículo como **colateral**, esse veículo específico vira uma ordem de repossessão. Neste caso, o card da missão mostra a placa real do veículo — ao localizar o veículo e rebocá-lo até o impound, o saldo da dívida do devedor é automaticamente reduzido.

### Blip do agente (v16)
O dono do veículo (em missões PVP/Stealth) recebe um **blip no mapa** mostrando a posição aproximada do agente Repo Man durante a missão. Fique atento — o agente também sabe onde você está.

### Pagamento
- Motorista recebe **15% do valor do veículo** × multiplicador do tipo
- Empresa recebe **20% adicional** no caixa

### Abandono
- Clique em **Abandonar Missão** a qualquer momento
- A ordem volta para a lista de disponíveis
- Não há penalidade, mas a ordem pode expirar enquanto você está na missão

---

## Indústrias

Empresas podem comprar matéria-prima e vender produtos nas indústrias espalhadas pelo mapa.

### Tipos de indústria
- **Primária** — só vende (ex: Ron Alternates — vende Combustível)
- **Secundária** — compra matéria-prima e vende produto processado (ex: Fleeca Foods — compra Carne e Água, vende Comida Processada)
- **Terciária** — só compra (ex: 24/7 Distribution — compra Comida)

### Preços dinâmicos
Os preços mudam a cada 20 minutos com base na oferta e demanda. O preço nunca cai abaixo de 50% nem sobe acima de 200% do valor base.

---

## Certificações ADR (Cargas Perigosas)

Certas cargas exigem uma **Certificação ADR** válida antes de aceitar o job. Sem ela, o job aparece bloqueado na lista com um cadeado.

### Tipos de certificação
| Tipo | Exemplos de carga |
|---|---|
| Líquido Inflamável | Combustível, etanol |
| Gás Inflamável | GLP, propano |
| Tóxico | Pesticidas, produtos químicos |
| Corrosivo | Ácido, bateria industrial |
| Explosivo | Munição, fogos de artifício |
| Ambiental | Resíduos, materiais radioativos |

### Como obter
1. Vá ao NPC Examinador ADR no **Terminal Portuário A1** (marcado no mapa)
2. Pague a taxa de exame
3. Responda corretamente **2 de 3 perguntas** de múltipla escolha
4. A certificação é concedida e válida por **30 dias**

### Renovação
- Renove **sem refazer o exame**: pague 60% da taxa no NPC Examinador ou diretamente no menu PDA (aba **ADR**)
- Certidões expiradas ficam visíveis no menu mas precisam ser renovadas antes de aceitar jobs bloqueados

### Cooldown de re-tentativa
Em caso de reprovação, aguarde **30 minutos** antes de tentar novamente. A taxa de exame não é reembolsada.

---

## Empilhadeira (Forklift)

Alguns jobs de entrega carregam **múltiplos pallets** (indicado no card com o badge *Forklift rec.*). Você pode carregá-los manualmente ou usar uma empilhadeira.

### Carregamento manual
- Para cada pallet, uma barra de progresso individual aparece
- Mais lento, mas sem custo adicional

### Alugando uma empilhadeira
1. Vá a um dos pontos de aluguel marcados no mapa
2. Interaja com o NPC → **Alugar Empilhadeira ($500)** — cobrado do seu banco
3. Use a empilhadeira para carregar os pallets fisicamente no caminhão
4. Ao terminar, **devolva** a empilhadeira no ponto de origem para recuperar **$250** (50%)

### Mini-job de Trade Point
Além dos jobs de entrega normais, alguns locais de logística (Walker Logistics, Pacific Shipyard) oferecem **mini-jobs de empilhadeira**:
- Alugue a empilhadeira no local
- Carregue **5 pallets** no caminhão NPC dentro do tempo limite
- Receba pagamento com bônus por velocidade:
  - Até 90 segundos: **×1.3**
  - Até 150 segundos: **×1.0**
  - Acima de 150 segundos: **×0.7**

---

## Roubo de Carga

Se você deixar seu caminhão **parado sem motorista por 30 segundos** durante um job ativo, a carga fica **vulnerável a roubo**.

### Para o dono da carga
- Uma notificação aparece avisando que a carga está vulnerável
- Se você tiver **GPS Tracker** instalado no veículo, receberá a localização exata quando o roubo começar
- Volte ao caminhão para cancelar a vulnerabilidade
- Se a carga for roubada, o job é encerrado sem pagamento

### Para ladrões
- Um indicador visual aparece sobre caminhões vulneráveis próximos
- Interaja com o caminhão via **ox_target** para iniciar o roubo
- Uma barra de progresso de **20 segundos** deve ser completada sem interrupção
- Após o roubo, a carga é transferida para o seu veículo — entregue no destino original
- O pagamento é calculado sobre o valor base da carga com **bônus de +25%** e depende do seu tempo de entrega

### GPS Tracker
Empresas podem instalar um **GPS Tracker** em seus veículos para proteger a carga:
- Custo: **$5.000** cobrado do caixa da empresa
- Menu → **Garagem** → selecione o veículo → **Instalar GPS Tracker**
- Com o tracker ativo, o dono é notificado com a localização exata ao início de qualquer tentativa de roubo
- A polícia também é alertada com uma referência aproximada da zona

---

## Dicas

- **Priorize jobs de alto valor e longa distância** para ativar os bônus de Valuable e Distance ao mesmo tempo
- **Mantenha a integridade da carga acima de 85%** — a skill Fragile só ativa se você entregar a carga em boas condições
- **Nunca deixe o caminhão sozido por mais de 30s** durante um job — a carga fica vulnerável a roubo
- **GPS Tracker vale o investimento** em rotas longas ou em regiões com alto tráfego de jogadores
- **Pague as parcelas do empréstimo em dia** — a multa de 15% pode dobrar sua dívida ao longo do tempo
- **Empresas Repo Man** são mais lucrativas por missão mas exigem ação imediata antes da expiração
- **Invista em Speed primeiro** — é o único bônus de skill que funciona em qualquer job, reduzindo penalidades por atraso
- **Renove as certidões ADR antes de expirarem** — a renovação custa 60% da taxa e não exige re-exame
