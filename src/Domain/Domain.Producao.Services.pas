{*******************************************************************************
  Domain.Producao.Services

  As regras de negocio do chao de fabrica, em dois servicos:

    ENGENHARIA  - mantem a estrutura (BOM) e o roteiro, explode a arvore de
                  materiais e calcula o custo padrao por acumulacao (roll-up)

    PRODUCAO    - conduz a ordem: criar -> liberar (requisita material) ->
                  apontar (registra o que a fabrica fez) -> concluir (apura
                  o custo real e a variacao contra o padrao)

  ESTUDO - os pontos mais instrutivos daqui:

    * RECURSAO EM GRAFO com deteccao de ciclo.
      Uma estrutura de produto e um grafo dirigido aciclico (DAG). Se alguem
      cadastrar "A leva B" e depois "B leva A", a explosao entra em recursao
      infinita e derruba o sistema. O servico recusa isso ANTES de gravar.

    * CONGELAMENTO (snapshot).
      Ao criar a OP, copiamos estrutura e roteiro para dentro dela. A OP de
      hoje nao muda porque a engenharia alterou a receita amanha.

    * CUSTEIO PADRAO x REAL.
      A entrada do produto acabado no estoque e feita pelo custo PADRAO
      (previsivel). No fechamento, comparamos com o REAL e apuramos a
      VARIACAO - exatamente como um ERP industrial faz.

    * O servico devolve TResultado<T> nas falhas esperadas (falta material,
      falta estrutura) e lanca excecao nas impossiveis (OP inexistente).
*******************************************************************************}
unit Domain.Producao.Services;

interface

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  System.Generics.Defaults,
  Core.Types,
  Core.Logger,
  Core.Events,
  Domain.Entities,
  Domain.Enums,
  Domain.Events,
  Domain.Interfaces,
  Domain.Producao,
  Domain.Services;

type
  { ==========================================================================
    ENGENHARIA DE PRODUTO
    ========================================================================== }
  IServicoEngenharia = interface
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D30}']
    // --- estrutura ---
    function DefinirComponente(AProdutoPaiId, AComponenteId: Integer;
      AQuantidade: Double; APerdaPercentual: Double = 0): TItemEstrutura;
    procedure RemoverComponente(AProdutoPaiId, AComponenteId: Integer);
    function Estrutura(AProdutoPaiId: Integer): TArray<TItemEstrutura>;
    /// Explosao MULTINIVEL: desce a arvore inteira somando quantidades.
    function Explodir(AProdutoId: Integer;
      AQuantidade: Double = 1): TArray<TLinhaExplosao>;
    /// Necessidade liquida so de itens COMPRADOS (folhas da arvore).
    function NecessidadeDeCompra(AProdutoId: Integer;
      AQuantidade: Double): TArray<TLinhaExplosao>;
    /// Verifica se ligar pai->componente criaria um ciclo na estrutura.
    function CriariaCiclo(AProdutoPaiId, AComponenteId: Integer): Boolean;

    // --- roteiro ---
    function DefinirOperacao(AProdutoId, ASequencia: Integer;
      const ADescricao: string; ACentroId: Integer;
      ATempoSetupMin, ATempoUnitarioMin: Double): TOperacaoRoteiro;
    procedure RemoverOperacao(AProdutoId, ASequencia: Integer);
    function Roteiro(AProdutoId: Integer): TArray<TOperacaoRoteiro>;
    function TempoDoLote(AProdutoId: Integer; AQuantidade: Double): Double;

    // --- custo ---
    /// Custo padrao do item: material (recursivo) + transformacao (roteiro).
    function CustoPadrao(AProdutoId: Integer): Currency;
    function CustoMaterialPadrao(AProdutoId: Integer): Currency;
    function CustoOperacionalPadrao(AProdutoId: Integer;
      AQuantidade: Double = 1): Currency;
  end;

  TServicoEngenharia = class(TInterfacedObject, IServicoEngenharia)
  private
    FProdutos: IRepositorioProdutos;
    FEstruturas: IRepositorioEstruturas;
    FRoteiros: IRepositorioRoteiros;
    FCentros: IRepositorioCentros;
    FLogger: ILogger;
    procedure ExplodirRecursivo(AProdutoId: Integer; AQuantidade: Double;
      ANivel: Integer; AAcumulador: TList<TLinhaExplosao>;
      AVisitados: TList<Integer>);
    function ContemNaArvore(ARaizId, AProcuradoId: Integer;
      AProfundidade: Integer): Boolean;
  public
    constructor Create(const AProdutos: IRepositorioProdutos;
      const AEstruturas: IRepositorioEstruturas;
      const ARoteiros: IRepositorioRoteiros;
      const ACentros: IRepositorioCentros; const ALogger: ILogger);

    function DefinirComponente(AProdutoPaiId, AComponenteId: Integer;
      AQuantidade: Double; APerdaPercentual: Double = 0): TItemEstrutura;
    procedure RemoverComponente(AProdutoPaiId, AComponenteId: Integer);
    function Estrutura(AProdutoPaiId: Integer): TArray<TItemEstrutura>;
    function Explodir(AProdutoId: Integer;
      AQuantidade: Double = 1): TArray<TLinhaExplosao>;
    function NecessidadeDeCompra(AProdutoId: Integer;
      AQuantidade: Double): TArray<TLinhaExplosao>;
    function CriariaCiclo(AProdutoPaiId, AComponenteId: Integer): Boolean;

    function DefinirOperacao(AProdutoId, ASequencia: Integer;
      const ADescricao: string; ACentroId: Integer;
      ATempoSetupMin, ATempoUnitarioMin: Double): TOperacaoRoteiro;
    procedure RemoverOperacao(AProdutoId, ASequencia: Integer);
    function Roteiro(AProdutoId: Integer): TArray<TOperacaoRoteiro>;
    function TempoDoLote(AProdutoId: Integer; AQuantidade: Double): Double;

    function CustoPadrao(AProdutoId: Integer): Currency;
    function CustoMaterialPadrao(AProdutoId: Integer): Currency;
    function CustoOperacionalPadrao(AProdutoId: Integer;
      AQuantidade: Double = 1): Currency;
  end;

  { ==========================================================================
    CONTROLE DA PRODUCAO
    ========================================================================== }

  /// Resultado do fechamento da OP: o que se aprendeu sobre o custo.
  TFechamentoOP = record
    CustoPrevisto: Currency;
    CustoReal: Currency;
    Variacao: Currency;         // real - previsto ajustado a producao
    VariacaoPercentual: Double;
    QuantidadeProduzida: Double;
    QuantidadeRefugada: Double;
    IndiceRefugo: Double;       // refugo / (bom + refugo)
    CustoUnitario: Currency;
    function Resumo: string;
  end;

  IServicoProducao = interface
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D31}']
    function CriarOrdem(AProdutoId: Integer; AQuantidade: Double;
      ADataPrevista: TDateTime): TResultado<TOrdemProducao>;
    /// Lista o que falta em estoque para liberar a ordem (vazio = pode ir).
    function FaltaDeMaterial(AOrdemId: Integer): TArray<string>;
    /// Requisita (baixa) todos os componentes e libera a ordem para a fabrica.
    function LiberarOrdem(AOrdemId: Integer): TResultado<Currency>;
    /// Registra o que a fabrica produziu numa operacao do roteiro.
    function Apontar(AOrdemId, ASequenciaOperacao: Integer;
      AQuantidadeBoa, AQuantidadeRefugo, ATempoMinutos: Double;
      const AOperador: string;
      const AMotivoRefugo: string = ''): TResultado<Double>;
    function ConcluirOrdem(AOrdemId: Integer): TResultado<TFechamentoOP>;
    procedure CancelarOrdem(AOrdemId: Integer; const AMotivo: string);
    /// Carga (em minutos) por centro de trabalho nas ordens abertas.
    function CargaPorCentro: TArray<TPar<string, Double>>;
  end;

  TServicoProducao = class(TInterfacedObject, IServicoProducao)
  private
    FOrdens: IRepositorioOrdens;
    FProdutos: IRepositorioProdutos;
    FCentros: IRepositorioCentros;
    FEngenharia: IServicoEngenharia;
    FEstoque: IServicoEstoque;
    FEventos: IEventBus;
    FLogger: ILogger;
    FUoW: IUnitOfWork;
    function ObterOrdem(AOrdemId: Integer): TOrdemProducao;
    procedure MovimentarComponente(AOrdem: TOrdemProducao;
      AComponente: TComponenteOP; AQuantidade: Double; ATipo: TTipoMovimento);
  public
    constructor Create(const AOrdens: IRepositorioOrdens;
      const AProdutos: IRepositorioProdutos; const ACentros: IRepositorioCentros;
      const AEngenharia: IServicoEngenharia; const AEstoque: IServicoEstoque;
      const AEventos: IEventBus; const ALogger: ILogger;
      const AUoW: IUnitOfWork);

    function CriarOrdem(AProdutoId: Integer; AQuantidade: Double;
      ADataPrevista: TDateTime): TResultado<TOrdemProducao>;
    function FaltaDeMaterial(AOrdemId: Integer): TArray<string>;
    function LiberarOrdem(AOrdemId: Integer): TResultado<Currency>;
    function Apontar(AOrdemId, ASequenciaOperacao: Integer;
      AQuantidadeBoa, AQuantidadeRefugo, ATempoMinutos: Double;
      const AOperador: string;
      const AMotivoRefugo: string = ''): TResultado<Double>;
    function ConcluirOrdem(AOrdemId: Integer): TResultado<TFechamentoOP>;
    procedure CancelarOrdem(AOrdemId: Integer; const AMotivo: string);
    function CargaPorCentro: TArray<TPar<string, Double>>;
  end;

const
  /// Limite de profundidade da arvore: rede de seguranca contra ciclo.
  NIVEL_MAXIMO_ESTRUTURA = 12;

implementation

{ TFechamentoOP }

function TFechamentoOP.Resumo: string;
begin
  Result := Format(
    'Produzido %.2f (refugo %.2f = %.1f%%) | previsto %s | real %s | ' +
    'variacao %s (%.1f%%) | custo unitario %s',
    [QuantidadeProduzida, QuantidadeRefugada, IndiceRefugo * 100,
     TFmt.Moeda(CustoPrevisto), TFmt.Moeda(CustoReal), TFmt.Moeda(Variacao),
     VariacaoPercentual * 100, TFmt.Moeda(CustoUnitario)]);
end;

{ TServicoEngenharia }

constructor TServicoEngenharia.Create(const AProdutos: IRepositorioProdutos;
  const AEstruturas: IRepositorioEstruturas; const ARoteiros: IRepositorioRoteiros;
  const ACentros: IRepositorioCentros; const ALogger: ILogger);
begin
  inherited Create;
  FProdutos := AProdutos;
  FEstruturas := AEstruturas;
  FRoteiros := ARoteiros;
  FCentros := ACentros;
  FLogger := ALogger;
end;

function TServicoEngenharia.ContemNaArvore(ARaizId, AProcuradoId: Integer;
  AProfundidade: Integer): Boolean;
var
  LLinha: TItemEstrutura;
begin
  { Busca em profundidade: "AProcuradoId aparece em algum lugar da arvore
    de ARaizId?". O limite de profundidade e uma rede de seguranca caso ja
    exista um ciclo gravado por algum caminho (dados legados, por exemplo). }
  Result := False;
  if AProfundidade > NIVEL_MAXIMO_ESTRUTURA then
    Exit;

  for LLinha in FEstruturas.DoProdutoPai(ARaizId) do
  begin
    if LLinha.ComponenteId = AProcuradoId then
      Exit(True);
    if ContemNaArvore(LLinha.ComponenteId, AProcuradoId, AProfundidade + 1) then
      Exit(True);
  end;
end;

function TServicoEngenharia.CriariaCiclo(AProdutoPaiId, AComponenteId: Integer): Boolean;
begin
  // Ciclo direto (A leva A) ou indireto (A leva B, B leva A).
  Result := (AProdutoPaiId = AComponenteId) or
            ContemNaArvore(AComponenteId, AProdutoPaiId, 0);
end;

function TServicoEngenharia.DefinirComponente(AProdutoPaiId, AComponenteId: Integer;
  AQuantidade: Double; APerdaPercentual: Double): TItemEstrutura;
var
  LPai, LComponente: TProduto;
  LLinha: TItemEstrutura;
begin
  LPai := FProdutos.PorId(AProdutoPaiId);
  LComponente := FProdutos.PorId(AComponenteId);

  if AQuantidade <= 0 then
    raise EDominio.Create('A quantidade na estrutura deve ser maior que zero.');

  if not LPai.EhFabricado then
    raise EDominio.CreateFmt(
      'So itens fabricados tem estrutura. "%s" esta cadastrado como %s.',
      [LPai.Descricao, TipoProdutoDescr(LPai.Tipo)]);

  if CriariaCiclo(AProdutoPaiId, AComponenteId) then
    raise EDominio.CreateFmt(
      'Estrutura circular recusada: "%s" ja depende de "%s" (direta ou ' +
      'indiretamente). Isso deixaria a explosao em recursao infinita.',
      [LComponente.Descricao, LPai.Descricao]);

  // Ja existe a linha? Entao e atualizacao, nao duplicacao.
  LLinha := FEstruturas.Linha(AProdutoPaiId, AComponenteId);
  if LLinha <> nil then
  begin
    LLinha.Quantidade := AQuantidade;
    LLinha.PerdaPercentual := APerdaPercentual;
    LLinha.CodigoComponente := LComponente.Codigo;
    LLinha.DescricaoComponente := LComponente.Descricao;
    FEstruturas.Atualizar(LLinha);
    Exit(LLinha);
  end;

  LLinha := TItemEstrutura.Create;
  try
    LLinha.ProdutoPaiId := AProdutoPaiId;
    LLinha.ComponenteId := AComponenteId;
    LLinha.CodigoComponente := LComponente.Codigo;
    LLinha.DescricaoComponente := LComponente.Descricao;
    LLinha.Quantidade := AQuantidade;
    LLinha.PerdaPercentual := APerdaPercentual;
    LLinha.Sequencia := (Length(FEstruturas.DoProdutoPai(AProdutoPaiId)) + 1) * 10;
    LLinha.Validar;
    Result := FEstruturas.Adicionar(LLinha);
  except
    LLinha.Free;
    raise;
  end;

  FLogger.Info('Estrutura: %s agora leva %.4f de %s',
    [LPai.Codigo, AQuantidade, LComponente.Codigo]);
end;

procedure TServicoEngenharia.RemoverComponente(AProdutoPaiId, AComponenteId: Integer);
var
  LLinha: TItemEstrutura;
begin
  LLinha := FEstruturas.Linha(AProdutoPaiId, AComponenteId);
  if LLinha = nil then
    raise EDominio.Create('Esse componente nao esta na estrutura do item.');
  FEstruturas.Remover(LLinha.Id);
end;

function TServicoEngenharia.Estrutura(AProdutoPaiId: Integer): TArray<TItemEstrutura>;
begin
  Result := FEstruturas.DoProdutoPai(AProdutoPaiId);
end;

procedure TServicoEngenharia.ExplodirRecursivo(AProdutoId: Integer;
  AQuantidade: Double; ANivel: Integer; AAcumulador: TList<TLinhaExplosao>;
  AVisitados: TList<Integer>);
var
  LLinha: TItemEstrutura;
  LProduto: TProduto;
  LSaida: TLinhaExplosao;
  LQuantidadeFilho: Double;
begin
  if ANivel > NIVEL_MAXIMO_ESTRUTURA then
    raise EDominio.CreateFmt(
      'Estrutura com mais de %d niveis: provavel ciclo nos dados.',
      [NIVEL_MAXIMO_ESTRUTURA]);

  for LLinha in FEstruturas.DoProdutoPai(AProdutoId) do
  begin
    if not FProdutos.TentarPorId(LLinha.ComponenteId, LProduto) then
      Continue;

    // Quantidade BRUTA: ja embute a perda tecnica da linha.
    LQuantidadeFilho := LLinha.QuantidadeBruta * AQuantidade;

    LSaida := Default(TLinhaExplosao);
    LSaida.Nivel := ANivel;
    LSaida.ProdutoId := LProduto.Id;
    LSaida.Codigo := LProduto.Codigo;
    LSaida.Descricao := LProduto.Descricao;
    LSaida.Tipo := LProduto.Tipo;
    LSaida.QuantidadeUnitaria := LLinha.QuantidadeBruta;
    LSaida.QuantidadeTotal := LQuantidadeFilho;
    LSaida.CustoUnitario := LProduto.CustoMedio;
    AAcumulador.Add(LSaida);

    // Desce um nivel: o componente pode ter a propria receita.
    if AVisitados.IndexOf(LProduto.Id) >= 0 then
      Continue;   // protecao extra contra ciclo ja gravado
    AVisitados.Add(LProduto.Id);
    try
      ExplodirRecursivo(LProduto.Id, LQuantidadeFilho, ANivel + 1,
        AAcumulador, AVisitados);
    finally
      AVisitados.Remove(LProduto.Id);
    end;
  end;
end;

function TServicoEngenharia.Explodir(AProdutoId: Integer;
  AQuantidade: Double): TArray<TLinhaExplosao>;
var
  LLista: TList<TLinhaExplosao>;
  LVisitados: TList<Integer>;
begin
  LLista := TList<TLinhaExplosao>.Create;
  LVisitados := TList<Integer>.Create;
  try
    LVisitados.Add(AProdutoId);
    ExplodirRecursivo(AProdutoId, AQuantidade, 0, LLista, LVisitados);
    Result := LLista.ToArray;
  finally
    LVisitados.Free;
    LLista.Free;
  end;
end;

function TServicoEngenharia.NecessidadeDeCompra(AProdutoId: Integer;
  AQuantidade: Double): TArray<TLinhaExplosao>;
var
  LTudo: TArray<TLinhaExplosao>;
  LLinha: TLinhaExplosao;
  LMapa: TDictionary<Integer, TLinhaExplosao>;
  LAtual: TLinhaExplosao;
begin
  { So as FOLHAS compradas interessam para compras. Itens fabricados viram
    outras ordens de producao, nao pedidos de compra.
    Como o mesmo componente pode aparecer em varios ramos, somamos por item. }
  LMapa := TDictionary<Integer, TLinhaExplosao>.Create;
  try
    LTudo := Explodir(AProdutoId, AQuantidade);
    for LLinha in LTudo do
    begin
      if not (LLinha.Tipo in TIPOS_COMPRADOS) then
        Continue;

      if LMapa.TryGetValue(LLinha.ProdutoId, LAtual) then
      begin
        LAtual.QuantidadeTotal := LAtual.QuantidadeTotal + LLinha.QuantidadeTotal;
        LMapa.AddOrSetValue(LLinha.ProdutoId, LAtual);
      end
      else
      begin
        LAtual := LLinha;
        LAtual.Nivel := 0;  // consolidado: o nivel perde o sentido
        LMapa.Add(LLinha.ProdutoId, LAtual);
      end;
    end;

    Result := LMapa.Values.ToArray;
    TArray.Sort<TLinhaExplosao>(Result, TComparer<TLinhaExplosao>.Construct(
      function(const A, B: TLinhaExplosao): Integer
      begin
        Result := CompareStr(A.Codigo, B.Codigo);
      end));
  finally
    LMapa.Free;
  end;
end;

function TServicoEngenharia.DefinirOperacao(AProdutoId, ASequencia: Integer;
  const ADescricao: string; ACentroId: Integer;
  ATempoSetupMin, ATempoUnitarioMin: Double): TOperacaoRoteiro;
var
  LProduto: TProduto;
  LCentro: TCentroTrabalho;
  LOperacao: TOperacaoRoteiro;
begin
  LProduto := FProdutos.PorId(AProdutoId);
  LCentro := FCentros.PorId(ACentroId);

  if not LProduto.EhFabricado then
    raise EDominio.CreateFmt('So itens fabricados tem roteiro ("%s" e %s).',
      [LProduto.Descricao, TipoProdutoDescr(LProduto.Tipo)]);

  LOperacao := FRoteiros.Operacao(AProdutoId, ASequencia);
  if LOperacao <> nil then
  begin
    LOperacao.Descricao := ADescricao;
    LOperacao.CentroId := LCentro.Id;
    LOperacao.CodigoCentro := LCentro.Codigo;
    LOperacao.TempoSetupMin := ATempoSetupMin;
    LOperacao.TempoUnitarioMin := ATempoUnitarioMin;
    FRoteiros.Atualizar(LOperacao);
    Exit(LOperacao);
  end;

  LOperacao := TOperacaoRoteiro.Create;
  try
    LOperacao.ProdutoId := AProdutoId;
    LOperacao.Sequencia := ASequencia;
    LOperacao.Descricao := ADescricao;
    LOperacao.CentroId := LCentro.Id;
    LOperacao.CodigoCentro := LCentro.Codigo;
    LOperacao.TempoSetupMin := ATempoSetupMin;
    LOperacao.TempoUnitarioMin := ATempoUnitarioMin;
    LOperacao.Validar;
    Result := FRoteiros.Adicionar(LOperacao);
  except
    LOperacao.Free;
    raise;
  end;
end;

procedure TServicoEngenharia.RemoverOperacao(AProdutoId, ASequencia: Integer);
var
  LOperacao: TOperacaoRoteiro;
begin
  LOperacao := FRoteiros.Operacao(AProdutoId, ASequencia);
  if LOperacao = nil then
    raise EDominio.Create('Operacao inexistente no roteiro.');
  FRoteiros.Remover(LOperacao.Id);
end;

function TServicoEngenharia.Roteiro(AProdutoId: Integer): TArray<TOperacaoRoteiro>;
begin
  Result := FRoteiros.DoProduto(AProdutoId);
end;

function TServicoEngenharia.TempoDoLote(AProdutoId: Integer;
  AQuantidade: Double): Double;
var
  LOperacao: TOperacaoRoteiro;
begin
  Result := 0;
  for LOperacao in FRoteiros.DoProduto(AProdutoId) do
    Result := Result + LOperacao.TempoParaLote(AQuantidade);
end;

function TServicoEngenharia.CustoMaterialPadrao(AProdutoId: Integer): Currency;
var
  LLinha: TItemEstrutura;
  LComponente: TProduto;
begin
  { ROLL-UP DE CUSTO: o custo de um item fabricado e a soma dos custos dos
    componentes. Se o componente tambem e fabricado, desce mais um nivel.
    A recursao termina nas materias-primas, que tem custo medio proprio. }
  Result := 0;
  for LLinha in FEstruturas.DoProdutoPai(AProdutoId) do
  begin
    if not FProdutos.TentarPorId(LLinha.ComponenteId, LComponente) then
      Continue;

    if LComponente.EhFabricado then
      Result := Result + RoundTo(LLinha.QuantidadeBruta *
        CustoPadrao(LComponente.Id), -4)
    else
      Result := Result + RoundTo(LLinha.QuantidadeBruta *
        LComponente.CustoMedio, -4);
  end;
end;

function TServicoEngenharia.CustoOperacionalPadrao(AProdutoId: Integer;
  AQuantidade: Double): Currency;
var
  LOperacao: TOperacaoRoteiro;
  LCentro: TCentroTrabalho;
begin
  Result := 0;
  for LOperacao in FRoteiros.DoProduto(AProdutoId) do
    if FCentros.TentarPorId(LOperacao.CentroId, LCentro) then
      Result := Result + LCentro.CustoDeMinutos(
        LOperacao.TempoParaLote(AQuantidade));
end;

function TServicoEngenharia.CustoPadrao(AProdutoId: Integer): Currency;
var
  LProduto: TProduto;
begin
  LProduto := FProdutos.PorId(AProdutoId);
  if not LProduto.EhFabricado then
    Exit(LProduto.CustoMedio);

  // Material + transformacao, para UMA unidade.
  Result := CustoMaterialPadrao(AProdutoId) + CustoOperacionalPadrao(AProdutoId, 1);
end;

{ TServicoProducao }

constructor TServicoProducao.Create(const AOrdens: IRepositorioOrdens;
  const AProdutos: IRepositorioProdutos; const ACentros: IRepositorioCentros;
  const AEngenharia: IServicoEngenharia; const AEstoque: IServicoEstoque;
  const AEventos: IEventBus; const ALogger: ILogger; const AUoW: IUnitOfWork);
begin
  inherited Create;
  FOrdens := AOrdens;
  FProdutos := AProdutos;
  FCentros := ACentros;
  FEngenharia := AEngenharia;
  FEstoque := AEstoque;
  FEventos := AEventos;
  FLogger := ALogger;
  FUoW := AUoW;
end;

function TServicoProducao.ObterOrdem(AOrdemId: Integer): TOrdemProducao;
begin
  Result := FOrdens.PorId(AOrdemId);
end;

function TServicoProducao.CriarOrdem(AProdutoId: Integer; AQuantidade: Double;
  ADataPrevista: TDateTime): TResultado<TOrdemProducao>;
var
  LProduto: TProduto;
  LOrdem: TOrdemProducao;
  LComponentes: TArray<TItemEstrutura>;
  LLinha: TItemEstrutura;
  LComponente: TProduto;
  LOperacoes: TArray<TOperacaoRoteiro>;
  LOperacao: TOperacaoRoteiro;
  LCentro: TCentroTrabalho;
  LCustoMaterial, LCustoOperacional: Currency;
begin
  LProduto := FProdutos.PorId(AProdutoId);

  if AQuantidade <= 0 then
    Exit(TResultado<TOrdemProducao>.Falha(
      'A quantidade da ordem deve ser maior que zero.'));

  if not LProduto.EhFabricado then
    Exit(TResultado<TOrdemProducao>.FalhaFmt(
      'O item "%s" e do tipo %s: nao se fabrica, se compra.',
      [LProduto.Descricao, TipoProdutoDescr(LProduto.Tipo)]));

  LComponentes := FEngenharia.Estrutura(AProdutoId);
  if Length(LComponentes) = 0 then
    Exit(TResultado<TOrdemProducao>.FalhaFmt(
      'O item "%s" nao tem estrutura cadastrada. Sem receita nao ha ordem.',
      [LProduto.Codigo]));

  LOperacoes := FEngenharia.Roteiro(AProdutoId);
  if Length(LOperacoes) = 0 then
    Exit(TResultado<TOrdemProducao>.FalhaFmt(
      'O item "%s" nao tem roteiro cadastrado.', [LProduto.Codigo]));

  LOrdem := TOrdemProducao.Create;
  try
    LOrdem.Numero := FOrdens.ProximoNumero;
    LOrdem.ProdutoId := LProduto.Id;
    LOrdem.CodigoProduto := LProduto.Codigo;
    LOrdem.DescricaoProduto := LProduto.Descricao;
    LOrdem.QuantidadePlanejada := AQuantidade;
    LOrdem.DataPrevista := ADataPrevista;

    { CONGELAMENTO: a estrutura e o roteiro de HOJE entram na ordem.
      Mudancas futuras da engenharia nao afetam esta OP. }
    LCustoMaterial := 0;
    for LLinha in LComponentes do
    begin
      if not FProdutos.TentarPorId(LLinha.ComponenteId, LComponente) then
        Continue;
      LOrdem.AdicionarComponente(LComponente.Id, LComponente.Codigo,
        LComponente.Descricao, LLinha.QuantidadeBruta * AQuantidade,
        LComponente.CustoMedio);
      LCustoMaterial := LCustoMaterial +
        RoundTo(LLinha.QuantidadeBruta * AQuantidade * LComponente.CustoMedio, -2);
    end;

    LCustoOperacional := 0;
    for LOperacao in LOperacoes do
    begin
      if not FCentros.TentarPorId(LOperacao.CentroId, LCentro) then
        Continue;
      LOrdem.AdicionarOperacao(LOperacao.Sequencia, LOperacao.Descricao,
        LCentro.Id, LCentro.Codigo, LOperacao.TempoParaLote(AQuantidade),
        LCentro.CustoHora);
      LCustoOperacional := LCustoOperacional +
        LCentro.CustoDeMinutos(LOperacao.TempoParaLote(AQuantidade));
    end;

    LOrdem.CustoMaterialPrevisto := LCustoMaterial;
    LOrdem.CustoOperacionalPrevisto := LCustoOperacional;
    LOrdem.Validar;

    Result := TResultado<TOrdemProducao>.Ok(FOrdens.Adicionar(LOrdem));
  except
    LOrdem.Free;
    raise;
  end;

  FLogger.Info('OP %s criada: %.2f x %s (previsto %s)',
    [Result.Valor.Numero, AQuantidade, LProduto.Codigo,
     TFmt.Moeda(Result.Valor.CustoPrevisto)]);
end;

function TServicoProducao.FaltaDeMaterial(AOrdemId: Integer): TArray<string>;
var
  LOrdem: TOrdemProducao;
  LComponente: TComponenteOP;
  LProduto: TProduto;
  LFaltas: TList<string>;
begin
  LOrdem := ObterOrdem(AOrdemId);
  LFaltas := TList<string>.Create;
  try
    for LComponente in LOrdem.Componentes do
    begin
      if not FProdutos.TentarPorId(LComponente.ProdutoId, LProduto) then
      begin
        LFaltas.Add(Format('Componente %d saiu do cadastro.',
          [LComponente.ProdutoId]));
        Continue;
      end;
      // Estoque e inteiro; a necessidade e fracionaria -> arredonda para cima.
      if LProduto.Estoque < Ceil(LComponente.SaldoAConsumir) then
        LFaltas.Add(Format('%s: precisa %.3f, tem %d',
          [LProduto.Codigo, LComponente.SaldoAConsumir, LProduto.Estoque]));
    end;
    Result := LFaltas.ToArray;
  finally
    LFaltas.Free;
  end;
end;

procedure TServicoProducao.MovimentarComponente(AOrdem: TOrdemProducao;
  AComponente: TComponenteOP; AQuantidade: Double; ATipo: TTipoMovimento);
var
  LProduto: TProduto;
  LQuantidadeInteira: Integer;
begin
  if AQuantidade <= 0 then
    Exit;
  if not FProdutos.TentarPorId(AComponente.ProdutoId, LProduto) then
    Exit;

  LQuantidadeInteira := Ceil(AQuantidade);
  if ATipo = tmConsumo then
    FEstoque.RequisitarParaOrdem(LProduto.Id, LQuantidadeInteira, AOrdem.Id,
      Format('Requisicao da OP %s', [AOrdem.Numero]))
  else
    FEstoque.DevolverDaOrdem(LProduto.Id, LQuantidadeInteira, AOrdem.Id,
      Format('Devolucao da OP %s', [AOrdem.Numero]));
end;

function TServicoProducao.LiberarOrdem(AOrdemId: Integer): TResultado<Currency>;
var
  LOrdem: TOrdemProducao;
  LFaltas: TArray<string>;
  LComponente: TComponenteOP;
  LProduto: TProduto;
  LCustoReal: Currency;
begin
  LOrdem := ObterOrdem(AOrdemId);

  if LOrdem.Status <> opPlanejada then
    Exit(TResultado<Currency>.FalhaFmt('A OP %s ja esta %s.',
      [LOrdem.Numero, StatusOPDescr(LOrdem.Status)]));

  LFaltas := FaltaDeMaterial(AOrdemId);
  if Length(LFaltas) > 0 then
  begin
    FEventos.Publicar(TFaltaDeMaterial.Create(LOrdem.Id, LOrdem.Numero,
      string.Join(' | ', LFaltas)));
    Exit(TResultado<Currency>.Falha('Falta material: ' +
      string.Join(' | ', LFaltas)));
  end;

  LCustoReal := 0;

  { Tudo dentro de uma transacao: se a baixa do 5o componente falhar, os
    4 primeiros voltam para o estoque (compensacao do Unit of Work). }
  FUoW.Executar(
    procedure
    var
      { A variavel do "for" precisa ser local DESTE bloco: uma variavel
        capturada de fora vive no frame do metodo anonimo e o compilador
        recusa usa-la como controle de laco (E1019). }
      LItem: TComponenteOP;
      LProdutoDoItem: TProduto;
    begin
      for LItem in LOrdem.Componentes do
      begin
        MovimentarComponente(LOrdem, LItem, LItem.SaldoAConsumir, tmConsumo);

        if FProdutos.TentarPorId(LItem.ProdutoId, LProdutoDoItem) then
          LItem.CustoUnitario := LProdutoDoItem.CustoMedio;

        LItem.QuantidadeConsumida := LItem.QuantidadeNecessaria;
        LCustoReal := LCustoReal + LItem.CustoTotal;
      end;

      LOrdem.CustoMaterialReal := LCustoReal;
      LOrdem.MudarStatus(opLiberada);
      FOrdens.Atualizar(LOrdem);
    end);

  FEventos.Publicar(TOrdemLiberada.Create(LOrdem.Id, LOrdem.Numero,
    LOrdem.CodigoProduto, LOrdem.QuantidadePlanejada, LCustoReal));

  Result := TResultado<Currency>.Ok(LCustoReal);
end;

function TServicoProducao.Apontar(AOrdemId, ASequenciaOperacao: Integer;
  AQuantidadeBoa, AQuantidadeRefugo, ATempoMinutos: Double;
  const AOperador, AMotivoRefugo: string): TResultado<Double>;
var
  LOrdem: TOrdemProducao;
  LOperacao: TOperacaoOP;
  LEhUltima: Boolean;
  LCustoPadraoUnitario: Currency;
  LEntrada: Integer;
begin
  LOrdem := ObterOrdem(AOrdemId);

  if not (LOrdem.Status in OP_EM_ANDAMENTO) then
    Exit(TResultado<Double>.FalhaFmt(
      'Nao da para apontar na OP %s: ela esta %s.',
      [LOrdem.Numero, StatusOPDescr(LOrdem.Status)]));

  LOperacao := LOrdem.OperacaoDaSequencia(ASequenciaOperacao);
  if LOperacao = nil then
    Exit(TResultado<Double>.FalhaFmt('A OP %s nao tem a operacao %d.',
      [LOrdem.Numero, ASequenciaOperacao]));

  if AQuantidadeBoa + LOrdem.QuantidadeProduzida > LOrdem.QuantidadePlanejada then
    Exit(TResultado<Double>.FalhaFmt(
      'Apontamento acima do planejado: a OP %s pede %.2f e ja tem %.2f.',
      [LOrdem.Numero, LOrdem.QuantidadePlanejada, LOrdem.QuantidadeProduzida]));

  LEhUltima := LOperacao.Sequencia =
    LOrdem.Operacoes[LOrdem.Operacoes.Count - 1].Sequencia;

  LCustoPadraoUnitario := 0;
  if LOrdem.QuantidadePlanejada > 0 then
    LCustoPadraoUnitario := RoundTo(
      LOrdem.CustoPrevisto / LOrdem.QuantidadePlanejada, -4);

  FUoW.Executar(
    procedure
    begin
      LOrdem.RegistrarApontamento(ASequenciaOperacao, AQuantidadeBoa,
        AQuantidadeRefugo, ATempoMinutos, AOperador, AMotivoRefugo);

      // Custo de transformacao realizado: tempo apontado x custo/hora.
      LOrdem.CustoOperacionalReal := LOrdem.CustoOperacionalReal +
        RoundTo((ATempoMinutos / 60) * LOperacao.CustoHora, -2);

      { Somente a ULTIMA operacao entrega produto ao estoque, e a entrada e
        pelo CUSTO PADRAO. A diferenca contra o real vira variacao no
        fechamento da ordem. }
      LEntrada := Trunc(AQuantidadeBoa);
      if LEhUltima and (LEntrada > 0) then
        FEstoque.EntradaDeProducao(LOrdem.ProdutoId, LEntrada, LOrdem.Id,
          LCustoPadraoUnitario,
          Format('Producao da OP %s', [LOrdem.Numero]));

      FOrdens.Atualizar(LOrdem);
    end);

  FEventos.Publicar(TApontamentoRegistrado.Create(LOrdem.Id, LOrdem.Numero,
    ASequenciaOperacao, AQuantidadeBoa, AQuantidadeRefugo, AOperador));

  Result := TResultado<Double>.Ok(LOrdem.QuantidadeProduzida);
end;

function TServicoProducao.ConcluirOrdem(AOrdemId: Integer): TResultado<TFechamentoOP>;
var
  LOrdem: TOrdemProducao;
  LFechamento: TFechamentoOP;
  LOperacao: TOperacaoOP;
  LPrevistoAjustado: Currency;
  LTotalApontado: Double;
begin
  LOrdem := ObterOrdem(AOrdemId);

  if not LOrdem.PodeMudarPara(opConcluida) then
    Exit(TResultado<TFechamentoOP>.FalhaFmt(
      'A OP %s nao pode ser concluida no status %s.',
      [LOrdem.Numero, StatusOPDescr(LOrdem.Status)]));

  if LOrdem.QuantidadeProduzida <= 0 then
    Exit(TResultado<TFechamentoOP>.Falha(
      'Nao ha producao apontada: nada a concluir.'));

  FUoW.Executar(
    procedure
    var
      LItem: TOperacaoOP;
    begin
      for LItem in LOrdem.Operacoes do
        LItem.Status := soConcluida;
      LOrdem.MudarStatus(opConcluida);
      FOrdens.Atualizar(LOrdem);
    end);

  { VARIACAO DE CUSTO: comparamos o real contra o previsto AJUSTADO a
    quantidade efetivamente produzida. Comparar contra o previsto cheio
    quando se produziu metade seria enganoso. }
  LPrevistoAjustado := 0;
  if LOrdem.QuantidadePlanejada > 0 then
    LPrevistoAjustado := RoundTo(LOrdem.CustoPrevisto *
      (LOrdem.QuantidadeProduzida / LOrdem.QuantidadePlanejada), -2);

  LFechamento := Default(TFechamentoOP);
  LFechamento.CustoPrevisto := LPrevistoAjustado;
  LFechamento.CustoReal := LOrdem.CustoReal;
  LFechamento.Variacao := LOrdem.CustoReal - LPrevistoAjustado;
  if LPrevistoAjustado > 0 then
    LFechamento.VariacaoPercentual := LFechamento.Variacao / LPrevistoAjustado;
  LFechamento.QuantidadeProduzida := LOrdem.QuantidadeProduzida;
  LFechamento.QuantidadeRefugada := LOrdem.QuantidadeRefugada;
  LTotalApontado := LOrdem.QuantidadeProduzida + LOrdem.QuantidadeRefugada;
  if LTotalApontado > 0 then
    LFechamento.IndiceRefugo := LOrdem.QuantidadeRefugada / LTotalApontado;
  LFechamento.CustoUnitario := LOrdem.CustoUnitarioReal;

  FEventos.Publicar(TOrdemConcluida.Create(LOrdem.Id, LOrdem.Numero,
    LOrdem.QuantidadeProduzida, LOrdem.QuantidadeRefugada,
    LFechamento.Variacao));

  FLogger.Info('OP %s concluida. %s', [LOrdem.Numero, LFechamento.Resumo]);
  Result := TResultado<TFechamentoOP>.Ok(LFechamento);
end;

procedure TServicoProducao.CancelarOrdem(AOrdemId: Integer; const AMotivo: string);
var
  LOrdem: TOrdemProducao;
  LComponente: TComponenteOP;
begin
  LOrdem := ObterOrdem(AOrdemId);

  if not LOrdem.PodeMudarPara(opCancelada) then
    raise EDominio.CreateFmt('A OP %s (%s) nao pode mais ser cancelada.',
      [LOrdem.Numero, StatusOPDescr(LOrdem.Status)]);

  FUoW.Executar(
    procedure
    var
      LItem: TComponenteOP;
    begin
      // O que foi requisitado e nao consumido volta para o almoxarifado.
      if LOrdem.ConsumiuMaterial then
        for LItem in LOrdem.Componentes do
        begin
          MovimentarComponente(LOrdem, LItem, LItem.QuantidadeConsumida, tmEntrada);
          LItem.QuantidadeConsumida := 0;
        end;

      LOrdem.CustoMaterialReal := 0;
      LOrdem.Observacao := Copy(Trim(LOrdem.Observacao +
        ' [CANCELADA: ' + AMotivo + ']'), 1, 200);
      LOrdem.MudarStatus(opCancelada);
      FOrdens.Atualizar(LOrdem);
    end);

  FLogger.Aviso('OP %s cancelada: %s', [LOrdem.Numero, AMotivo]);
end;

function TServicoProducao.CargaPorCentro: TArray<TPar<string, Double>>;
var
  LOrdem: TOrdemProducao;
  LOperacao: TOperacaoOP;
  LMapa: TDictionary<string, Double>;
  LMinutos: Double;
  LChave: string;
  LLista: TList<TPar<string, Double>>;
begin
  LMapa := TDictionary<string, Double>.Create;
  LLista := TList<TPar<string, Double>>.Create;
  try
    for LOrdem in FOrdens.ComStatus(OP_ABERTAS) do
      for LOperacao in LOrdem.Operacoes do
      begin
        if LOperacao.Status = soConcluida then
          Continue;
        LMapa.TryGetValue(LOperacao.CodigoCentro, LMinutos);
        LMapa.AddOrSetValue(LOperacao.CodigoCentro,
          LMinutos + Max(0, LOperacao.TempoPrevistoMin - LOperacao.TempoRealizadoMin));
      end;

    for LChave in LMapa.Keys do
      LLista.Add(TPar<string, Double>.Criar(LChave, LMapa[LChave]));

    Result := LLista.ToArray;
    TArray.Sort<TPar<string, Double>>(Result,
      TComparer<TPar<string, Double>>.Construct(
        function(const A, B: TPar<string, Double>): Integer
        begin
          if B.Valor > A.Valor then
            Result := 1
          else if B.Valor < A.Valor then
            Result := -1
          else
            Result := 0;
        end));
  finally
    LLista.Free;
    LMapa.Free;
  end;
end;

end.
