# ERP Industrial — projeto de estudo em Delphi

Um sistema completo, em Object Pascal moderno, feito para **ler, quebrar e reconstruir**.
Roda em qualquer edição do Delphi, inclusive a **Starter** (que é a instalada aqui).

O domínio é um ERP industrial: clientes, produtos, estoque, pedidos, pagamentos
e — o que diferencia um ERP de fábrica de um comercial — o **módulo de PCP**:
estrutura de produto (BOM multinível), roteiro de fabricação, centros de trabalho,
ordens de produção, apontamento de chão de fábrica e custeio padrão × real.

Os dados podem ficar **em memória** (padrão, zero dependência) ou no **Firebird**
(cliente/servidor, como um ERP de verdade). A troca é uma opção de linha de comando:
nenhuma regra de negócio muda.

---

## Dois programas, um sistema

O projeto tem **duas interfaces de usuário sobre exatamente o mesmo domínio**:

| Projeto | O que é | Para que serve |
|---|---|---|
| `ERPVisual.dproj` | **Aplicação VCL com telas** | usar o sistema de verdade, clicando |
| `GestaoComercial.dproj` | Aplicação console | demonstração narrada, testes automatizados |

Isso não é redundância: é a prova de que a arquitetura funciona. Compare as
listas de units dos dois `.dpr` — `src\Core`, `src\Domain` e `src\Infra` são
**idênticos**. Só a camada de cima muda:

```
GestaoComercial.dpr  →  App.Console.pas   (Writeln / Readln)
ERPVisual.dpr        →  UI.Principal.pas  (TForm / TListView / TTreeView)
```

Se algum dia você precisar mexer em `src\Domain` para uma tela funcionar,
é sinal de que a regra de negócio estava no lugar errado.

### As telas

`ERPVisual.exe` abre uma janela com abas:

| Aba | O que tem |
|---|---|
| **Painel** | Indicadores + posição de estoque, com marcação de itens a repor |
| **Produtos** | Grade + ficha de cadastro (tipo, unidade, custo, estoque mínimo) |
| **Clientes** | Grade + ficha, com crédito disponível calculado ao vivo |
| **Pedidos** | Pedidos e seus itens; botões confirmar / pagar / cancelar |
| **Engenharia** | **Árvore da estrutura de produto** (TTreeView) + roteiro de fabricação |
| **Produção** | Ordens + lista de material congelada + roteiro com previsto × realizado |
| **Relatórios** | Todos os relatórios, inclusive curva ABC e ficha de custo |
| **Sistema** | Mural de eventos de domínio e log da sessão |

O **apontamento de produção** tem formulário próprio (`UI.Apontamento`), com
sugestão da próxima operação pendente e campo de motivo que só habilita quando
há refugo — a tela mais usada no chão de fábrica merece esse cuidado.

Menu *Arquivo* troca entre memória e Firebird **sem fechar o programa**.

---

## Como rodar

**Com telas:**

1. Abra `ERPVisual.dproj` no Delphi (File → Open Project).
2. `F9`. O executável sai em `build\ERPVisual.exe`.
3. `ERPVisual.exe --db` usa o Firebird em vez de memória.

**Console (demo e testes):**

1. Abra `GestaoComercial.dproj` no Delphi.
2. `Shift+F9` para compilar, `F9` para rodar.
3. O executável sai em `build\GestaoComercial.exe`.

> **Sobre a edição Starter:** o `dcc32` recusa compilar pela linha de comando
> ("This version of the product does not support command line compiling").
> Mas a própria IDE aceita build em lote, o que dá um atalho útil:
> ```
> "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\bds.exe" -pDelphi -b GestaoComercial.dproj
> ```
> Os erros ficam em `GestaoComercial.err`, na pasta do projeto.
>
> Guarde os fontes em **CRLF**. O RAD Studio reclama de arquivos com LF.

### Modos de execução

| Comando | O que faz |
|---|---|
| `GestaoComercial.exe` | Menu interativo (comercial + engenharia + produção) |
| `GestaoComercial.exe --demo` | **Comece por aqui.** Roteiro automático narrado, 19 passos |
| `GestaoComercial.exe --testes` | Roda a suíte de 63 testes. `ExitCode` 0 = tudo passou |
| `GestaoComercial.exe --vazamentos` | Liga o detector de memory leaks do Delphi |
| `GestaoComercial.exe --db` | Usa o **Firebird** em vez de memória (combine com os outros) |
| `GestaoComercial.exe --dbcriar` | Cria o banco e aplica o schema |
| `GestaoComercial.exe --dbscript` | Imprime o DDL (`--dbscript > bd\schema.sql`) |

Combine à vontade: `GestaoComercial.exe --testes --vazamentos`,
`GestaoComercial.exe --testes --db` (acrescenta os testes de persistência real).
Para passar parâmetros pela IDE: *Run → Parameters → Parameters*.

Estado verificado: **compila sem erros, 63/63 testes passando, zero vazamentos
de memória** nos modos `--testes` e `--demo`.

---

---

## Ligando o Firebird

O código do banco está pronto e compilado, mas depende de um servidor no ar.

### 1. Subir o servidor (uma vez, como administrador)

O Firebird abre a base de segurança (`security5.fdb`) e os arquivos de lock
dentro de `C:\Program Files\...`, onde um usuário comum **não tem permissão de
escrita**. Rodar sem privilégio faz toda conexão falhar com
*"Your user name and password are not defined"* — mesmo com a senha certa.

Clique com o botão direito em `ferramentas\iniciar_firebird.bat` →
**Executar como administrador**, e escolha:

- **1 = serviço** (recomendado): sobe junto com o Windows, resolve de vez;
- **2 = aplicação**: fica no ar só enquanto a janela existir.

Equivalente na mão, num prompt de administrador:

```bat
"C:\Program Files\Firebird\Firebird_5_0\instsvc.exe" install
"C:\Program Files\Firebird\Firebird_5_0\instsvc.exe" start
```

Conferir: `powershell -c "(Test-NetConnection 127.0.0.1 -Port 3050).TcpTestSucceeded"`

### 2. Criar o banco e o schema

```bat
build\GestaoComercial.exe --dbcriar
```

Isso cria `dados\ERP.FDB` (chamando o `isql` da instalação) e aplica todo o DDL.
É **idempotente**: rodar de novo não quebra nada.

### 3. Usar

```bat
build\GestaoComercial.exe --db            REM menu usando Firebird
build\GestaoComercial.exe --demo --db     REM demonstração gravando no banco
build\GestaoComercial.exe --testes --db   REM soma os testes de persistência real
```

### Configuração

`build\firebird.ini` (criado automaticamente se faltar):

```ini
[Firebird]
Servidor=localhost
Porta=3050
Caminho=...\dados\ERP.FDB
Usuario=SYSDBA
Senha=...
VendorLib=C:\Program Files\Firebird\Firebird_5_0\WOW64\fbclient.dll
CharacterSet=UTF8
```

> ⚠️ **A senha fica em texto puro nesse arquivo.** Aceitável num projeto de
> estudo com banco local; em produção se usa um usuário dedicado com permissão
> mínima e configuração fora do diretório da aplicação.

### Três armadilhas que custam horas

1. **Arquitetura da DLL.** O Delphi Starter só gera **32 bits**. Numa instalação
   x64 do Firebird, a `fbclient.dll` de 32 bits está em `WOW64\`. Apontar para a
   de 64 bits dá *"is not a valid Win32 application"*.
2. **Embedded não serve aqui.** O modo embutido precisa do `engine13.dll` na
   mesma arquitetura do executável; a pasta `WOW64\plugins` traz só o `chacha.dll`.
   Por isso o projeto usa **cliente/servidor via TCP** — que, aliás, é o normal
   num ERP.
3. **Firebird 5 não aceita mais `masterkey`.** A senha do SYSDBA é definida na
   instalação; se você não a tem, redefina com `gsec` ou reinstale.

---

## Arquitetura

Dependências apontam **sempre para dentro**. `Domain` não conhece ninguém.

```
        ┌─────────────────────────────────────────┐
        │                  App                    │  menu, relatórios, bootstrap
        │  ┌───────────────────────────────────┐  │
        │  │             Domain                │  │  entidades, regras, contratos
        │  │   entidades + interfaces (contra- │  │
        │  │   tos que a infra deve cumprir)   │  │
        │  └───────────────────────────────────┘  │
        │                 Infra                   │  memória, JSON, gateway
        └─────────────────────────────────────────┘
                          Core                       utilidades genéricas
```

| Camada | Papel | Pode usar |
|---|---|---|
| **Core** | Utilidades sem regra de negócio (log, container, eventos, RTTI, JSON) | só a RTL |
| **Domain** | Entidades, regras e **interfaces** de repositório/serviço | Core |
| **Infra** | Implementa os contratos do domínio | Core, Domain |
| **App** | Monta tudo e conversa com o usuário | tudo |

O teste decisivo: para trocar "memória" por "Firebird", você mexe em **um único arquivo**
(`App.Bootstrap.pas`). Nenhuma regra de negócio muda.

---

## Mapa: onde está cada conceito

| Quero estudar… | Vá para | O que ver |
|---|---|---|
| Records avançados, generics em record | `Core.Types.pas` | `TResultado<T>` — o padrão "Result" no lugar de exceção |
| Hierarquia de exceções | `Core.Types.pas` | `EDominio`, `EValidacao`, `ENaoEncontrado` |
| Interfaces + ARC (contagem de referência) | `Core.Logger.pas` | `TInterfacedObject`, quando **não** chamar `Free` |
| **Ciclos de referência com métodos anônimos** | `Core.Container.pas`, `App.Bootstrap.pas` | ver a seção dedicada abaixo — foi um vazamento real deste projeto |
| Template Method, Composite, Decorator, Null Object | `Core.Logger.pas` | 4 padrões em um arquivo pequeno |
| Injeção de dependência / IoC | `Core.Container.pas` | `TypeInfo`, `GetTypeData`, `Supports`, escopos, ciclo |
| Observer / Mediator, métodos anônimos | `Core.Events.pas` | despacho por hierarquia de classe, isolamento de falha |
| **Atributos customizados + RTTI** | `Core.Validation.pas` | validação declarativa: `[Obrigatorio] [TamanhoMax(80)]` |
| Serialização automática via RTTI | `Core.Json.pas` | `TValue`, `TTypeKind`, datas em ISO-8601 |
| Máquina de estados | `Domain.Enums.pas` | `TransicaoPermitida`, conjuntos (`set of`) |
| **Modelo rico / Aggregate Root** | `Domain.Entities.pas` | `TPedido` protege seus itens e seus totais |
| Herança, virtual/override/abstract | `Domain.Entities.pas` | `Clone`, `ToJson`, `Validar` |
| Specification pattern | `Domain.Specifications.pas` | filtros que se combinam com `E`, `Ou`, `Nao` |
| Inversão de dependência (o "D" de SOLID) | `Domain.Interfaces.pas` | o domínio **declara** o que precisa |
| Strategy | `Domain.Services.pas` | `IPoliticaDesconto` e a composta "melhor desconto" |
| Orquestração de caso de uso | `Domain.Services.pas` | `ConfirmarPedido`: 5 validações e um ponto sem volta |
| Classes genéricas | `Infra.Repositories.pas` | um CRUD genérico serve todas as entidades |
| Thread-safety | `Infra.Repositories.pas` | `TCriticalSection` |
| Unit of Work / Command (undo) | `Infra.UnitOfWork.pas` | rollback por compensação, em ordem inversa |
| Dublês de teste (stub/fake) | `Infra.Gateway.pas` | isolar serviço externo atrás de interface |
| Generics com `constructor` constraint | `Infra.Persistence.pas` | `<T: TEntidade, constructor>` |
| Composition root | `App.Bootstrap.pas` | o único lugar que conhece as classes concretas |
| Agrupamento e ordenação | `App.Reports.pas` | `TDictionary`, `TArray.Sort`, curva ABC (Pareto) |
| Tratamento de erro na fronteira | `App.Console.pas` | usuário nunca vê stack trace |
| Como um framework de teste funciona | `Tests.Framework.pas` | ~200 linhas, escrito do zero |
| Testes como documentação | `Tests.Suite.pas` | 63 testes, cada um é uma regra explicada |
| **Recursão em grafo + ciclo** | `Domain.Producao.Services.pas` | explosão de estrutura multinível e recusa de BOM circular |
| Snapshot / congelamento | `Domain.Producao.Services.pas` | a OP copia estrutura e roteiro na abertura |
| Custeio padrão × real | `Domain.Producao.Services.pas` | entrada pelo padrão, variação apurada no fecho |
| Custo médio móvel | `Domain.Entities.pas` | `AtualizarCustoMedio` — média ponderada na entrada |
| Agregado com 3 coleções filhas | `Domain.Producao.pas` | `TOrdemProducao` e sua destruição em cascata |
| **Data Mapper + Identity Map** | `Infra.Repositories.Firebird.pas` | os dois padrões de ORM que fazem tudo funcionar |
| Geração de SQL por RTTI | `Infra.Mapping.pas` | mini-ORM com o mapeamento fora do domínio |
| FireDAC na prática | `Infra.Database.pas` | conexão, parâmetros, transação, console |
| DDL idempotente | `Infra.Schema.pas` | criar o schema sem medo de rodar duas vezes |
| Transação real + compensação | `Infra.UnitOfWork.pas` | `TUnitOfWorkFirebird`: desfaz no banco **e** em memória |
| SQL recursivo (`WITH RECURSIVE`) | `bd/schema.sql` | a mesma explosão de BOM resolvida pelo banco |
| **VCL: formulário e `.dfm`** | `UI.Principal.pas/.dfm` | como um form é declarado em texto e aberto no designer |
| Alinhamento e splitters | `UI.Principal.dfm` | `alClient`/`alTop`/`alBottom` — layout que redimensiona sozinho |
| `TTreeView` recursivo | `UI.Principal.pas` | `MontarNo` desenha a BOM com a mesma recursão do serviço |
| Diálogo modal reutilizável | `UI.Apontamento.pas` | método de classe que cria, mostra e destrói o form |
| Manifesto e temas visuais | `src/UI/ERPVisual.manifest` | sem ele o app tem cara de 1998 |

---

## A armadilha que este projeto pisou (leia com atenção)

Na primeira versão, rodar `--testes --vazamentos` acusou **mais de mil objetos
vazados**. Nenhum `Free` faltando: eram **ciclos de referência**. Vale estudar,
porque é o tipo de bug que só aparece em produção, meses depois.

**Causa 1 — a fábrica que capturava o container.**
```pascal
// ERRADO: a closure captura o container...
TDI.Registrar<ILogger>(LContainer,
  function: IInterface
  begin
    Result := TConsoleLogger.Create;
  end);
```
…e o container guarda a closure. Contador nunca chega a zero → o container e
**tudo que ele criou** vazam. A correção foi passar o container por parâmetro
(`TFabricaServico`), para a closure não capturar nada.

**Causa 2 — o frame de variáveis locais.**
Todo método anônimo aninhado carrega uma referência ao *frame* de locais do
método onde foi escrito — **mesmo que não use nenhuma delas**. Então:

```pascal
procedure TAplicacao.RegistrarAssinaturas;
var
  LBus: IEventBus;      // <== esta linha era o vazamento
begin
  LBus := Eventos;
  TEventos.Assinar<TEstoqueBaixo>(LBus, procedure(E: TEstoqueBaixo) ... end);
```
Ciclo: `barramento → handler → frame → LBus → barramento`.
A correção foi não guardar o barramento numa local (chamar `Eventos`
diretamente) e usar o **campo** `FContainer` em vez de uma cópia local.

**Causa 3 — objeto passado direto para parâmetro `const` de interface.**
```pascal
Buscar(TPedidoDoCliente.Create(AClienteId));   // ERRADO: vaza
```
Parâmetros `const` de interface não geram contagem de referência: o objeto
nasce com contador zero e ninguém o destrói. A correção é guardar em uma
variável local do tipo da interface antes de passar.

**Como conferir:** `GestaoComercial.exe --testes --vazamentos`. Se o programa
fechar sozinho, está limpo. Se abrir um diálogo listando objetos, você
introduziu um vazamento. Faça isso depois de cada exercício.

---

## Roteiro de estudo sugerido

### Semana 1 — entender o que já existe
1. Rode `--demo` e leia a saída de cima a baixo.
2. Rode `--testes`. Os 43 passam? Ótimo, agora **quebre um de propósito**:
   mude `DescontoDaCategoria` em `Domain.Enums.pas` e veja quais testes falham.
3. Leia `Core.Types.pas` inteiro. É o arquivo mais simples e ensina record + generics.
4. Leia `Domain.Entities.pas`. Foque em `TPedido`: por que `Itens` é somente leitura?
5. Leia `Domain.Services.pas`, método `ConfirmarPedido`. Enumere as 5 verificações.

### Semana 2 — entender as amarrações
6. `Core.Container.pas`: acompanhe no depurador (F7/F8) uma chamada de
   `TDI.Resolver<IServicoVendas>` e veja a cascata de dependências nascendo.
7. `Core.Events.pas`: coloque um breakpoint em `Publicar` e veja o `while` subindo
   pela hierarquia de classes.
8. `Core.Validation.pas`: acompanhe `TValidador.Validar` com o depurador e veja
   a RTTI listando as propriedades.
9. `Infra.UnitOfWork.pas`: entenda por que o rollback é em ordem **inversa**.

### Semana 3 — modificar
10. Faça os exercícios abaixo, do 1 ao 15.

---

## Exercícios (em ordem crescente de dificuldade)

**Aquecimento**
1. Acrescente o campo `Peso: Double` em `TProduto`, com validação `[NaoNegativo]`,
   e mostre-o na listagem do menu.
2. Crie a categoria de cliente `ccDiamante` com 15% de desconto. Quantos arquivos
   você precisou tocar? (resposta esperada: 2)
3. Escreva um teste que garanta que um pedido sem itens **não** pode ser confirmado.

**Domínio**
4. Implemente `TPoliticaCupom`: um desconto fixo se o pedido tiver um código de
   cupom na observação. Registre-a na composição em `App.Bootstrap`.
5. Adicione o status `spEmSeparacao` entre `spPago` e `spEnviado`. Ajuste a máquina
   de estados e veja quais testes quebram.
6. Crie a entidade `TDevolucao` (pedido + itens devolvidos + motivo) com seu
   repositório, e faça a devolução voltar o estoque.
7. Faça `TPedido` recusar itens de produtos de categorias diferentes quando o
   frete for grátis (invente a regra e teste-a).

**Infra**
8. Escreva `TRepositorioCsv<T>` que salva em CSV em vez de JSON, usando RTTI.
9. Faça o `TArquivoLogger` girar o arquivo quando passar de 1 MB (`app.1.log`, etc.).
10. Implemente cache no `TRepositorioMemoria.Buscar`: memorize o resultado por
    `AEspec.Nome` e invalide em qualquer escrita.

**PCP / Industrial**
11a. Cadastre um terceiro nível na estrutura (um componente do tampo que também
    seja fabricado) e confira se a explosão e o custo continuam certos.
11b. Implemente **lote mínimo** e **múltiplo de compra** no MRP: se falta 3 mas
    o lote mínimo é 10, comprar 10.
11c. Implemente **apontamento por operação em sequência**: proibir apontar a
    operação 20 antes de a 10 ter quantidade suficiente.
11d. Implemente **rastreabilidade por lote**: número de lote na entrada, no
    consumo pela OP e na venda — depois responda "onde foi parar o lote X?".
11e. Gere OP **automaticamente** a partir de um pedido de venda de item
    fabricado sem estoque (`PedidoOrigemId` já existe na entidade).

**Banco de dados**
11f. Traduza `ISpecification<T>` para cláusula `WHERE` em vez de filtrar em
    memória. (Comece por um visitor sobre as specs concretas.)
11g. Faça o Identity Map perceber alteração externa: guarde `ATUALIZADOEM` e
    recarregue quando o banco tiver versão mais nova.
11h. Troque a estratégia "apaga e regrava" dos filhos por *diff* real
    (inserir/atualizar/excluir só o que mudou).

**Avançado**
11. Faça o container resolver dependências **automaticamente** por RTTI: leia os
    parâmetros do construtor e resolva cada um. (Dica: `TRttiMethod.GetParameters`.)
12. Torne o `TEventBus` assíncrono: publique numa fila e processe numa `TThread`
    separada, com `TMonitor` para sincronizar.
13. Implemente snapshot real no Unit of Work: em vez de compensação, clone as
    entidades no `Iniciar` e restaure-as no `Rollback` (use `TEntidade.Clone`).
14. ~~Crie uma segunda interface em VCL~~ — **já feito**: veja `ERPVisual.dproj`
    e `src\UI\`. Agora estenda: adicione uma aba de *Centros de trabalho* com
    cadastro, e uma de *Movimentações de estoque* com filtro por período.
    Continue valendo a regra: nada fora de `src\UI` pode mudar.
15. Meça: gere 100.000 pedidos e descubra o gargalo com o profiler. (Spoiler:
    `TRepositorioMemoria.Todos` ordena a cada chamada.) Corrija sem quebrar testes.

---

## Convenções usadas no código

| Convenção | Exemplo | Por quê |
|---|---|---|
| `T` para tipos | `TPedido` | padrão Delphi |
| `I` para interfaces | `IRepositorioPedidos` | padrão Delphi |
| `E` para exceções | `EDominio` | padrão Delphi |
| `F` para campos | `FNome` | *field* |
| `A` para argumentos | `AQuantidade` | evita colisão com campos |
| `L` para locais | `LPedido` | evita colisão com tudo |
| Nomes de negócio em português | `ConfirmarPedido` | o código deve falar a língua do negócio |
| Nomes técnicos em inglês | `IUnitOfWork`, `ISpecification` | são termos consagrados de literatura |

Sem acentos no código-fonte e nas mensagens de console: evita problemas de
*code page* no terminal do Windows.

---

## O módulo de PCP, em uma página

O vocabulário que separa um ERP industrial de um comercial:

| Termo | O que é | Onde está |
|---|---|---|
| **Estrutura / BOM** | A receita: 1 mesa = 1 tampo + 4 pés + 16 parafusos. É **multinível** — o tampo tem a própria receita | `TItemEstrutura` |
| **Perda técnica** | Se a receita pede 1 kg e a perda é 5%, a fábrica separa 1,0526 kg. Esquecer isso é a causa clássica de "faltou material no meio da OP" | `QuantidadeBruta` |
| **Roteiro** | A sequência de operações: 10-Corte, 20-Montagem, 30-Embalagem | `TOperacaoRoteiro` |
| **Setup × tempo unitário** | Preparação cobrada uma vez por lote; o resto é por peça | `TempoParaLote` |
| **Centro de trabalho** | Onde a operação acontece; tem capacidade (h/dia) e custo/hora | `TCentroTrabalho` |
| **Ordem de produção** | A autorização para fabricar. Ao abrir, **congela** estrutura e roteiro | `TOrdemProducao` |
| **Apontamento** | O que a fábrica reportou: boas, refugo, tempo, operador | `TApontamento` |
| **Roll-up de custo** | O custo do fabricado é a soma recursiva dos componentes + transformação | `CustoPadrao` |
| **Variação de custo** | Real − previsto ajustado à quantidade produzida | `TFechamentoOP` |
| **MRP** | Necessidade líquida = explosão − estoque | `NecessidadeDeCompra` |

### O fluxo completo

```
  ENGENHARIA            PCP                    CHÃO DE FÁBRICA          CUSTOS
  ──────────            ───                    ───────────────          ──────
  estrutura ─┐
  roteiro   ─┴──► criar OP (congela) ──► liberar ──► apontar ──► concluir
                       │                    │           │            │
                  custo previsto      baixa material  entrada     variação
                                      (requisição)   do acabado   real × padrão
                                                   (custo padrão)
```

Regras que o código faz cumprir:

- Só item **fabricado** tem estrutura e roteiro; matéria-prima se compra.
- **Estrutura circular é recusada** antes de gravar (A→B→C→A trava a explosão).
- A OP só existe se houver estrutura **e** roteiro cadastrados.
- Liberar sem material suficiente **falha** e não movimenta nada.
- Apontar acima do planejado é recusado; refugo **exige motivo**.
- Só a **última operação** do roteiro entrega produto ao estoque.
- A entrada é pelo **custo padrão**; a diferença vira variação no fechamento.
- Cancelar uma OP liberada **devolve** o material ao almoxarifado.

---

## Regras de negócio implementadas

- Pedido só aceita alteração de itens enquanto estiver em **Rascunho**.
- Transições de status seguem uma máquina de estados; qualquer salto é recusado.
- Confirmar um pedido exige, nesta ordem: pedido válido → cliente ativo →
  estoque disponível → desconto aplicado → crédito suficiente.
- Só então o estoque é baixado — dentro de uma transação com rollback.
- Cancelamento devolve ao estoque o que havia sido reservado.
- Preço do item é **congelado** no momento da venda (mudar o preço do produto
  depois não altera pedidos antigos).
- Crédito disponível = limite − soma dos pedidos em aberto.
- Estoque nunca fica negativo; ao cruzar o mínimo, um evento avisa Compras.
- Descontos não acumulam: aplica-se o mais vantajoso para o cliente.

---

## Estrutura de arquivos

```
ERPVisual.dpr              aplicacao COM TELAS (VCL)
ERPVisual.dproj            projeto visual para a IDE
GestaoComercial.dpr        aplicacao console (menu / demo / testes / banco)
GestaoComercial.dproj      projeto console para a IDE
bd/schema.sql              o DDL comentado, para leitura
ferramentas/               iniciar_firebird.bat (precisa de administrador)
src/
  Core/                    infraestrutura genérica, sem regra de negócio
    Core.Types.pas         exceções, TResultado<T>, TEnumUtils, formatação
    Core.Logger.pas        ILogger + 6 implementações (padrões de projeto)
    Core.Container.pas     container de injeção de dependência
    Core.Events.pas        barramento de eventos (observer)
    Core.Validation.pas    atributos de validação + validador por RTTI
    Core.Json.pas          serialização objeto <-> JSON por RTTI
  Domain/                  o coração: não depende de infraestrutura
    Domain.Enums.pas       status, categorias, máquina de estados
    Domain.Entities.pas    TCliente, TProduto, TPedido (aggregate root), ...
    Domain.Events.pas      eventos de domínio
    Domain.Specifications  filtros combináveis
    Domain.Interfaces.pas  contratos de repositório, UoW e gateway
    Domain.Services.pas    políticas de desconto, serviços de estoque e vendas
    Domain.Producao.pas    PCP: BOM, roteiro, centro, ordem, apontamento
    Domain.Producao.Services.pas  engenharia (explosão/custo) e produção
  Infra/                   implementações concretas dos contratos
    Infra.Repositories.pas repositórios genéricos em memória
    Infra.Mapping.pas      mini-ORM: mapeamento objeto→tabela por RTTI
    Infra.Database.pas     conexão FireDAC + configuração em .ini
    Infra.Schema.pas       DDL idempotente e limpeza de dados
    Infra.Repositories.Firebird.pas  os mesmos contratos, agora em SQL
    Infra.UnitOfWork.pas   transação por compensação (+ versão com banco)
    Infra.Gateway.pas      gateway de pagamento simulado + dublês
    Infra.Persistence.pas  persistência em JSON
  App/
    App.Bootstrap.pas      composition root (registra tudo no container)
    App.Seed.pas           dados de exemplo
    App.Reports.pas        relatórios e curva ABC
    App.Console.pas        menu interativo (console)
    App.Demo.pas           roteiro automático narrado
  UI/                      camada de apresentação VISUAL (VCL)
    UI.Principal.pas/.dfm  janela principal com as 8 abas
    UI.Apontamento.pas/.dfm  diálogo de apontamento de produção
    ERPVisual.manifest     manifesto de temas visuais
  Tests/
    Tests.Framework.pas    mini framework xUnit escrito do zero
    Tests.Suite.pas        43 testes = documentação executável
build/                     saída de compilação (exe, dcu)
build/dados/               JSONs gerados em tempo de execução (criados ao salvar)
```

---

## Perguntas para se fazer enquanto lê

- Por que `TPedido.Itens` é somente leitura, se a lista interna é mutável?
- Por que `ConfirmarPedido` devolve `TResultado<Currency>` mas `EnviarPedido`
  lança exceção? Qual o critério?
- Por que `IRepositorio<T>` não tem GUID e `IRepositorioClientes` tem?
- Quem destrói um `TEventoDominio` publicado? E um `TCliente` adicionado ao
  repositório? E um `TInterfacedObject` guardado numa interface?
- Por que `TEspec` guarda `ISpecification<T>` e não `TEspec<T>` nos campos
  `FA`/`FB`? O que aconteceria com a memória se guardasse o objeto?
- Se dois pedidos reservarem o último item ao mesmo tempo, o que acontece?
  (Dica: procure `TCriticalSection` — e pense se ele é suficiente.)
