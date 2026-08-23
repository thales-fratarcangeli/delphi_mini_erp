{*******************************************************************************
  Domain.Producao

  O modulo de PCP (Planejamento e Controle da Producao) - o que separa um ERP
  INDUSTRIAL de um comercial.

  O vocabulario classico, para quem nunca mexeu com chao de fabrica:

    ESTRUTURA DE PRODUTO (BOM, "Bill of Materials")
      A receita do item: para fazer 1 mesa, use 1 tampo + 4 pes + 16 parafusos.
      E MULTINIVEL: o tampo pode, por sua vez, ter a propria estrutura.

    ROTEIRO DE FABRICACAO
      A sequencia de operacoes e por onde passam: 10-Corte (serra),
      20-Furacao (furadeira), 30-Montagem (bancada). Cada operacao tem tempo de
      PREPARACAO (setup, uma vez por lote) e tempo UNITARIO (por peca).

    CENTRO DE TRABALHO
      Onde a operacao acontece: uma maquina, uma celula, uma bancada.
      Tem capacidade (horas/dia) e custo/hora - base do custo de transformacao.

    ORDEM DE PRODUCAO (OP)
      A autorizacao para fabricar X unidades. Ao ser criada, a estrutura e o
      roteiro sao COPIADOS para dentro dela ("congelados"): se a engenharia
      mudar a receita amanha, a OP de hoje continua com o que foi planejado.
      Isso e regra de ouro em ERP industrial - sem isso nao ha rastreabilidade.

    APONTAMENTO
      O registro do que a fabrica efetivamente produziu: quantidade boa,
      refugo, tempo gasto, em qual operacao, por quem.

  ESTUDO - conceitos de Delphi aqui:
    * Mais um agregado com filhos (TOrdemProducao possui componentes,
      operacoes e apontamentos) e destruicao em cascata
    * Copia profunda no Clone, com tres listas
    * Serializacao JSON de um objeto com multiplas colecoes filhas
    * Segunda maquina de estados independente (TStatusOP)
*******************************************************************************}
unit Domain.Producao;

interface

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.JSON,
  System.Generics.Collections,
  Core.Types,
  Core.Json,
  Core.Validation,
  Domain.Entities,
  Domain.Enums;

type
  { --------------------------------------------------------------------------
    CENTRO DE TRABALHO
    -------------------------------------------------------------------------- }
  TCentroTrabalho = class(TEntidade)
  private
    FCodigo: string;
    FDescricao: string;
    FCapacidadeHorasDia: Double;
    FCustoHora: Currency;
    FAtivo: Boolean;
  public
    constructor Create; override;
    function Resumo: string; override;
    /// Custo de ocupar este centro por N minutos.
    function CustoDeMinutos(AMinutos: Double): Currency;
    /// Capacidade do centro em minutos por dia.
    function CapacidadeMinutosDia: Double;

    [Rotulo('Codigo do centro')] [Obrigatorio] [TamanhoMax(15)]
    property Codigo: string read FCodigo write FCodigo;

    [Rotulo('Descricao')] [Obrigatorio] [TamanhoMax(60)]
    property Descricao: string read FDescricao write FDescricao;

    [Rotulo('Capacidade (h/dia)')] [Faixa(0.0, 24.0)]
    property CapacidadeHorasDia: Double read FCapacidadeHorasDia write FCapacidadeHorasDia;

    [Rotulo('Custo/hora')] [NaoNegativo]
    property CustoHora: Currency read FCustoHora write FCustoHora;

    property Ativo: Boolean read FAtivo write FAtivo;
  end;

  { --------------------------------------------------------------------------
    ITEM DE ESTRUTURA (uma linha da receita)
    -------------------------------------------------------------------------- }
  TItemEstrutura = class(TEntidade)
  private
    FProdutoPaiId: Integer;
    FComponenteId: Integer;
    FCodigoComponente: string;
    FDescricaoComponente: string;
    FQuantidade: Double;
    FPerdaPercentual: Double;
    FSequencia: Integer;
    function GetQuantidadeBruta: Double;
  public
    constructor Create; override;
    function Resumo: string; override;

    [Rotulo('Produto pai')] [Obrigatorio]
    property ProdutoPaiId: Integer read FProdutoPaiId write FProdutoPaiId;

    [Rotulo('Componente')] [Obrigatorio]
    property ComponenteId: Integer read FComponenteId write FComponenteId;

    property CodigoComponente: string read FCodigoComponente write FCodigoComponente;
    property DescricaoComponente: string read FDescricaoComponente write FDescricaoComponente;

    /// Quantidade LIQUIDA do componente para 1 unidade do pai.
    [Rotulo('Quantidade')] [Faixa(0.0001, 1000000.0)]
    property Quantidade: Double read FQuantidade write FQuantidade;

    { Perda tecnica prevista (0 a 1). Se a receita pede 1 kg e a perda e 5%,
      a fabrica precisa separar 1,0526 kg para sobrar 1 kg util.
      Esquecer isso e a causa classica de "faltou material no meio da OP". }
    [Rotulo('Perda tecnica')] [Faixa(0.0, 0.9)]
    property PerdaPercentual: Double read FPerdaPercentual write FPerdaPercentual;

    property Sequencia: Integer read FSequencia write FSequencia;

    /// Quantidade com a perda ja embutida (o que realmente sai do estoque).
    property QuantidadeBruta: Double read GetQuantidadeBruta;
  end;

  { --------------------------------------------------------------------------
    OPERACAO DE ROTEIRO (um passo do processo)
    -------------------------------------------------------------------------- }
  TOperacaoRoteiro = class(TEntidade)
  private
    FProdutoId: Integer;
    FSequencia: Integer;
    FDescricao: string;
    FCentroId: Integer;
    FCodigoCentro: string;
    FTempoSetupMin: Double;
    FTempoUnitarioMin: Double;
  public
    constructor Create; override;
    function Resumo: string; override;
    /// Tempo total (setup + unitario x quantidade) para um lote.
    function TempoParaLote(AQuantidade: Double): Double;

    [Rotulo('Produto')] [Obrigatorio]
    property ProdutoId: Integer read FProdutoId write FProdutoId;

    [Rotulo('Sequencia')] [Faixa(1.0, 9999.0)]
    property Sequencia: Integer read FSequencia write FSequencia;

    [Rotulo('Descricao da operacao')] [Obrigatorio] [TamanhoMax(60)]
    property Descricao: string read FDescricao write FDescricao;

    [Rotulo('Centro de trabalho')] [Obrigatorio]
    property CentroId: Integer read FCentroId write FCentroId;

    property CodigoCentro: string read FCodigoCentro write FCodigoCentro;

    /// Tempo de preparacao da maquina: cobrado UMA vez por lote.
    [Rotulo('Tempo de setup (min)')] [NaoNegativo]
    property TempoSetupMin: Double read FTempoSetupMin write FTempoSetupMin;

    /// Tempo por peca.
    [Rotulo('Tempo unitario (min)')] [NaoNegativo]
    property TempoUnitarioMin: Double read FTempoUnitarioMin write FTempoUnitarioMin;
  end;

  { --------------------------------------------------------------------------
    COMPONENTE DA OP - a estrutura CONGELADA no momento da abertura
    -------------------------------------------------------------------------- }
  TComponenteOP = class(TEntidade)
  private
    FOrdemId: Integer;
    FProdutoId: Integer;
    FCodigoProduto: string;
    FDescricaoProduto: string;
    FQuantidadeNecessaria: Double;
    FQuantidadeConsumida: Double;
    FCustoUnitario: Currency;
    function GetSaldoAConsumir: Double;
    function GetCustoTotal: Currency;
  public
    constructor Create; override;
    function Resumo: string; override;

    property OrdemId: Integer read FOrdemId write FOrdemId;
    property ProdutoId: Integer read FProdutoId write FProdutoId;
    property CodigoProduto: string read FCodigoProduto write FCodigoProduto;
    property DescricaoProduto: string read FDescricaoProduto write FDescricaoProduto;
    property QuantidadeNecessaria: Double read FQuantidadeNecessaria write FQuantidadeNecessaria;
    property QuantidadeConsumida: Double read FQuantidadeConsumida write FQuantidadeConsumida;
    /// Custo medio do componente no momento em que foi consumido.
    property CustoUnitario: Currency read FCustoUnitario write FCustoUnitario;

    property SaldoAConsumir: Double read GetSaldoAConsumir;
    property CustoTotal: Currency read GetCustoTotal;
  end;

  { --------------------------------------------------------------------------
    OPERACAO DA OP - o roteiro CONGELADO, com o realizado
    -------------------------------------------------------------------------- }
  TOperacaoOP = class(TEntidade)
  private
    FOrdemId: Integer;
    FSequencia: Integer;
    FDescricao: string;
    FCentroId: Integer;
    FCodigoCentro: string;
    FTempoPrevistoMin: Double;
    FTempoRealizadoMin: Double;
    FQuantidadeBoa: Double;
    FQuantidadeRefugo: Double;
    FCustoHora: Currency;
    FStatus: TStatusOperacao;
    function GetEficiencia: Double;
    function GetCustoRealizado: Currency;
  public
    constructor Create; override;
    function Resumo: string; override;

    property OrdemId: Integer read FOrdemId write FOrdemId;
    property Sequencia: Integer read FSequencia write FSequencia;
    property Descricao: string read FDescricao write FDescricao;
    property CentroId: Integer read FCentroId write FCentroId;
    property CodigoCentro: string read FCodigoCentro write FCodigoCentro;
    property TempoPrevistoMin: Double read FTempoPrevistoMin write FTempoPrevistoMin;
    property TempoRealizadoMin: Double read FTempoRealizadoMin write FTempoRealizadoMin;
    property QuantidadeBoa: Double read FQuantidadeBoa write FQuantidadeBoa;
    property QuantidadeRefugo: Double read FQuantidadeRefugo write FQuantidadeRefugo;
    property CustoHora: Currency read FCustoHora write FCustoHora;
    property Status: TStatusOperacao read FStatus write FStatus;

    { Eficiencia = previsto / realizado.
      Acima de 1 significa que a fabrica foi mais rapida que o planejado;
      abaixo de 1, mais lenta. E o indicador mais cobrado no chao de fabrica. }
    property Eficiencia: Double read GetEficiencia;
    property CustoRealizado: Currency read GetCustoRealizado;
  end;

  { --------------------------------------------------------------------------
    APONTAMENTO - o que a fabrica reportou
    -------------------------------------------------------------------------- }
  TApontamento = class(TEntidade)
  private
    FOrdemId: Integer;
    FSequenciaOperacao: Integer;
    FQuantidadeBoa: Double;
    FQuantidadeRefugo: Double;
    FTempoMinutos: Double;
    FOperador: string;
    FMotivoRefugo: string;
  public
    constructor Create; override;
    function Resumo: string; override;

    property OrdemId: Integer read FOrdemId write FOrdemId;
    property SequenciaOperacao: Integer read FSequenciaOperacao write FSequenciaOperacao;

    [Rotulo('Quantidade boa')] [NaoNegativo]
    property QuantidadeBoa: Double read FQuantidadeBoa write FQuantidadeBoa;

    [Rotulo('Quantidade refugada')] [NaoNegativo]
    property QuantidadeRefugo: Double read FQuantidadeRefugo write FQuantidadeRefugo;

    [Rotulo('Tempo (min)')] [NaoNegativo]
    property TempoMinutos: Double read FTempoMinutos write FTempoMinutos;

    [Rotulo('Operador')] [Obrigatorio] [TamanhoMax(40)]
    property Operador: string read FOperador write FOperador;

    [Rotulo('Motivo do refugo')] [TamanhoMax(60)]
    property MotivoRefugo: string read FMotivoRefugo write FMotivoRefugo;
  end;

  { --------------------------------------------------------------------------
    ORDEM DE PRODUCAO - AGGREGATE ROOT com TRES colecoes filhas
    -------------------------------------------------------------------------- }
  TOrdemProducao = class(TEntidade)
  private
    FNumero: string;
    FProdutoId: Integer;
    FCodigoProduto: string;
    FDescricaoProduto: string;
    FQuantidadePlanejada: Double;
    FQuantidadeProduzida: Double;
    FQuantidadeRefugada: Double;
    FStatus: TStatusOP;
    FDataPrevista: TDateTime;
    FDataInicio: TDateTime;
    FDataFim: TDateTime;
    FCustoMaterialPrevisto: Currency;
    FCustoMaterialReal: Currency;
    FCustoOperacionalPrevisto: Currency;
    FCustoOperacionalReal: Currency;
    FPedidoOrigemId: Integer;
    FObservacao: string;
    FComponentes: TObjectList<TComponenteOP>;
    FOperacoes: TObjectList<TOperacaoOP>;
    FApontamentos: TObjectList<TApontamento>;
    function GetCustoPrevisto: Currency;
    function GetCustoReal: Currency;
    function GetCustoUnitarioReal: Currency;
    function GetSaldoAProduzir: Double;
    function GetPercentualConcluido: Double;
    function GetTempoPrevistoTotal: Double;
    function GetTempoRealizadoTotal: Double;
  protected
    procedure ValidarRegras(AErros: TList<string>); override;
  public
    constructor Create; override;
    destructor Destroy; override;

    // --- montagem (so enquanto planejada) ---
    function AdicionarComponente(AProdutoId: Integer;
      const ACodigo, ADescricao: string; AQuantidade: Double;
      ACustoUnitario: Currency): TComponenteOP;
    function AdicionarOperacao(ASequencia: Integer; const ADescricao: string;
      ACentroId: Integer; const ACodigoCentro: string;
      ATempoPrevisto: Double; ACustoHora: Currency): TOperacaoOP;
    function ComponenteDoProduto(AProdutoId: Integer): TComponenteOP;
    function OperacaoDaSequencia(ASequencia: Integer): TOperacaoOP;
    function ProximaOperacaoPendente: TOperacaoOP;

    // --- maquina de estados ---
    function PodeMudarPara(ANovo: TStatusOP): Boolean;
    procedure MudarStatus(ANovo: TStatusOP);
    function EstaAberta: Boolean;
    function ConsumiuMaterial: Boolean;

    // --- apontamento ---
    function RegistrarApontamento(ASequencia: Integer; AQuantidadeBoa,
      AQuantidadeRefugo, ATempoMinutos: Double;
      const AOperador, AMotivoRefugo: string): TApontamento;

    // --- ciclo de vida / serializacao ---
    function Clone: TEntidade; override;
    function ToJson: TJSONObject; override;
    procedure FromJson(AJson: TJSONObject); override;
    function Resumo: string; override;

    property Componentes: TObjectList<TComponenteOP> read FComponentes;
    property Operacoes: TObjectList<TOperacaoOP> read FOperacoes;
    property Apontamentos: TObjectList<TApontamento> read FApontamentos;

    [Rotulo('Numero da OP')] [Obrigatorio]
    property Numero: string read FNumero write FNumero;

    [Rotulo('Produto')] [Obrigatorio]
    property ProdutoId: Integer read FProdutoId write FProdutoId;

    property CodigoProduto: string read FCodigoProduto write FCodigoProduto;
    property DescricaoProduto: string read FDescricaoProduto write FDescricaoProduto;

    [Rotulo('Quantidade planejada')] [Faixa(0.0001, 1000000.0)]
    property QuantidadePlanejada: Double read FQuantidadePlanejada write FQuantidadePlanejada;

    property QuantidadeProduzida: Double read FQuantidadeProduzida write FQuantidadeProduzida;
    property QuantidadeRefugada: Double read FQuantidadeRefugada write FQuantidadeRefugada;
    property Status: TStatusOP read FStatus write FStatus;
    property DataPrevista: TDateTime read FDataPrevista write FDataPrevista;
    property DataInicio: TDateTime read FDataInicio write FDataInicio;
    property DataFim: TDateTime read FDataFim write FDataFim;

    property CustoMaterialPrevisto: Currency read FCustoMaterialPrevisto write FCustoMaterialPrevisto;
    property CustoMaterialReal: Currency read FCustoMaterialReal write FCustoMaterialReal;
    property CustoOperacionalPrevisto: Currency read FCustoOperacionalPrevisto write FCustoOperacionalPrevisto;
    property CustoOperacionalReal: Currency read FCustoOperacionalReal write FCustoOperacionalReal;

    /// Pedido de venda que originou a ordem (0 = producao para estoque).
    property PedidoOrigemId: Integer read FPedidoOrigemId write FPedidoOrigemId;

    [Rotulo('Observacao')] [TamanhoMax(200)]
    property Observacao: string read FObservacao write FObservacao;

    // Calculados (nao vao para o banco nem para o JSON)
    property CustoPrevisto: Currency read GetCustoPrevisto;
    property CustoReal: Currency read GetCustoReal;
    property CustoUnitarioReal: Currency read GetCustoUnitarioReal;
    property SaldoAProduzir: Double read GetSaldoAProduzir;
    property PercentualConcluido: Double read GetPercentualConcluido;
    property TempoPrevistoTotal: Double read GetTempoPrevistoTotal;
    property TempoRealizadoTotal: Double read GetTempoRealizadoTotal;
  end;

  /// Linha da explosao multinivel da estrutura (usada em relatorio e no MRP).
  TLinhaExplosao = record
    Nivel: Integer;
    ProdutoId: Integer;
    Codigo: string;
    Descricao: string;
    Tipo: TTipoProduto;
    QuantidadeUnitaria: Double;  // por 1 unidade do item de topo
    QuantidadeTotal: Double;     // para a quantidade pedida
    CustoUnitario: Currency;
    function Indentado: string;
  end;

implementation

{ TCentroTrabalho }

constructor TCentroTrabalho.Create;
begin
  inherited Create;
  FAtivo := True;
  FCapacidadeHorasDia := 8;
end;

function TCentroTrabalho.CapacidadeMinutosDia: Double;
begin
  Result := FCapacidadeHorasDia * 60;
end;

function TCentroTrabalho.CustoDeMinutos(AMinutos: Double): Currency;
begin
  Result := RoundTo((AMinutos / 60) * FCustoHora, -2);
end;

function TCentroTrabalho.Resumo: string;
begin
  Result := Format('#%d [%s] %s - %.1f h/dia - %s/h',
    [Id, FCodigo, FDescricao, FCapacidadeHorasDia, TFmt.Moeda(FCustoHora)]);
end;

{ TItemEstrutura }

constructor TItemEstrutura.Create;
begin
  inherited Create;
  FQuantidade := 1;
  FSequencia := 10;
end;

function TItemEstrutura.GetQuantidadeBruta: Double;
begin
  // 1 - perda no denominador: para SOBRAR a quantidade liquida apos a perda.
  if FPerdaPercentual >= 1 then
    Exit(FQuantidade);
  Result := FQuantidade / (1 - FPerdaPercentual);
end;

function TItemEstrutura.Resumo: string;
begin
  Result := Format('%3d) %-12s %-32s %10.4f (bruto %10.4f)',
    [FSequencia, FCodigoComponente, Copy(FDescricaoComponente, 1, 32),
     FQuantidade, GetQuantidadeBruta]);
end;

{ TOperacaoRoteiro }

constructor TOperacaoRoteiro.Create;
begin
  inherited Create;
  FSequencia := 10;
end;

function TOperacaoRoteiro.TempoParaLote(AQuantidade: Double): Double;
begin
  Result := FTempoSetupMin + (FTempoUnitarioMin * AQuantidade);
end;

function TOperacaoRoteiro.Resumo: string;
begin
  Result := Format('%3d) %-30s centro %-10s setup %6.1f min + %6.2f min/pc',
    [FSequencia, Copy(FDescricao, 1, 30), FCodigoCentro,
     FTempoSetupMin, FTempoUnitarioMin]);
end;

{ TComponenteOP }

constructor TComponenteOP.Create;
begin
  inherited Create;
end;

function TComponenteOP.GetSaldoAConsumir: Double;
begin
  Result := Max(0, FQuantidadeNecessaria - FQuantidadeConsumida);
end;

function TComponenteOP.GetCustoTotal: Currency;
begin
  Result := RoundTo(FQuantidadeConsumida * FCustoUnitario, -2);
end;

function TComponenteOP.Resumo: string;
begin
  Result := Format('%-12s %-30s nec %10.3f  cons %10.3f  %12s',
    [FCodigoProduto, Copy(FDescricaoProduto, 1, 30), FQuantidadeNecessaria,
     FQuantidadeConsumida, TFmt.Moeda(GetCustoTotal)]);
end;

{ TOperacaoOP }

constructor TOperacaoOP.Create;
begin
  inherited Create;
  FStatus := soPendente;
end;

function TOperacaoOP.GetEficiencia: Double;
begin
  if FTempoRealizadoMin <= 0 then
    Exit(0);
  Result := FTempoPrevistoMin / FTempoRealizadoMin;
end;

function TOperacaoOP.GetCustoRealizado: Currency;
begin
  Result := RoundTo((FTempoRealizadoMin / 60) * FCustoHora, -2);
end;

function TOperacaoOP.Resumo: string;
var
  LEficiencia: string;
begin
  if FTempoRealizadoMin > 0 then
    LEficiencia := Format('%5.0f%%', [GetEficiencia * 100])
  else
    LEficiencia := '    -';
  Result := Format('%3d) %-26s %-10s prev %7.1f  real %7.1f  ef %s  %s',
    [FSequencia, Copy(FDescricao, 1, 26), FCodigoCentro, FTempoPrevistoMin,
     FTempoRealizadoMin, LEficiencia, StatusOperacaoDescr(FStatus)]);
end;

{ TApontamento }

constructor TApontamento.Create;
begin
  inherited Create;
  FOperador := 'nao informado';
end;

function TApontamento.Resumo: string;
begin
  Result := Format('%s op %3d  boas %8.2f  refugo %8.2f  %7.1f min  %s%s',
    [TFmt.DataHora(CriadoEm), FSequenciaOperacao, FQuantidadeBoa,
     FQuantidadeRefugo, FTempoMinutos, FOperador,
     IfThen(FMotivoRefugo = '', '', ' (' + FMotivoRefugo + ')')]);
end;

{ TOrdemProducao }

constructor TOrdemProducao.Create;
begin
  inherited Create;
  FComponentes := TObjectList<TComponenteOP>.Create(True);
  FOperacoes := TObjectList<TOperacaoOP>.Create(True);
  FApontamentos := TObjectList<TApontamento>.Create(True);
  FStatus := opPlanejada;
  FQuantidadePlanejada := 1;
  FDataPrevista := Date;
end;

destructor TOrdemProducao.Destroy;
begin
  FApontamentos.Free;
  FOperacoes.Free;
  FComponentes.Free;
  inherited;
end;

function TOrdemProducao.AdicionarComponente(AProdutoId: Integer;
  const ACodigo, ADescricao: string; AQuantidade: Double;
  ACustoUnitario: Currency): TComponenteOP;
begin
  if FStatus <> opPlanejada then
    raise EDominio.CreateFmt(
      'A OP %s ja foi liberada; a lista de material esta congelada.', [FNumero]);

  Result := TComponenteOP.Create;
  Result.OrdemId := Id;
  Result.ProdutoId := AProdutoId;
  Result.CodigoProduto := ACodigo;
  Result.DescricaoProduto := ADescricao;
  Result.QuantidadeNecessaria := AQuantidade;
  Result.CustoUnitario := ACustoUnitario;
  FComponentes.Add(Result);
  MarcarAtualizado;
end;

function TOrdemProducao.AdicionarOperacao(ASequencia: Integer;
  const ADescricao: string; ACentroId: Integer; const ACodigoCentro: string;
  ATempoPrevisto: Double; ACustoHora: Currency): TOperacaoOP;
begin
  if FStatus <> opPlanejada then
    raise EDominio.CreateFmt(
      'A OP %s ja foi liberada; o roteiro esta congelado.', [FNumero]);

  Result := TOperacaoOP.Create;
  Result.OrdemId := Id;
  Result.Sequencia := ASequencia;
  Result.Descricao := ADescricao;
  Result.CentroId := ACentroId;
  Result.CodigoCentro := ACodigoCentro;
  Result.TempoPrevistoMin := ATempoPrevisto;
  Result.CustoHora := ACustoHora;
  FOperacoes.Add(Result);
  MarcarAtualizado;
end;

function TOrdemProducao.ComponenteDoProduto(AProdutoId: Integer): TComponenteOP;
var
  LItem: TComponenteOP;
begin
  for LItem in FComponentes do
    if LItem.ProdutoId = AProdutoId then
      Exit(LItem);
  Result := nil;
end;

function TOrdemProducao.OperacaoDaSequencia(ASequencia: Integer): TOperacaoOP;
var
  LItem: TOperacaoOP;
begin
  for LItem in FOperacoes do
    if LItem.Sequencia = ASequencia then
      Exit(LItem);
  Result := nil;
end;

function TOrdemProducao.ProximaOperacaoPendente: TOperacaoOP;
var
  LItem: TOperacaoOP;
begin
  Result := nil;
  for LItem in FOperacoes do
    if LItem.Status <> soConcluida then
      if (Result = nil) or (LItem.Sequencia < Result.Sequencia) then
        Result := LItem;
end;

function TOrdemProducao.PodeMudarPara(ANovo: TStatusOP): Boolean;
begin
  Result := TransicaoOPPermitida(FStatus, ANovo);
end;

procedure TOrdemProducao.MudarStatus(ANovo: TStatusOP);
begin
  if not PodeMudarPara(ANovo) then
    raise EDominio.CreateFmt('Transicao invalida na OP %s: %s -> %s.',
      [FNumero, StatusOPDescr(FStatus), StatusOPDescr(ANovo)]);

  FStatus := ANovo;
  case ANovo of
    opEmProducao:
      if FDataInicio = 0 then
        FDataInicio := Now;
    opConcluida, opCancelada:
      FDataFim := Now;
  end;
  MarcarAtualizado;
end;

function TOrdemProducao.EstaAberta: Boolean;
begin
  Result := FStatus in OP_ABERTAS;
end;

function TOrdemProducao.ConsumiuMaterial: Boolean;
begin
  Result := FStatus in OP_EM_ANDAMENTO;
end;

function TOrdemProducao.RegistrarApontamento(ASequencia: Integer;
  AQuantidadeBoa, AQuantidadeRefugo, ATempoMinutos: Double;
  const AOperador, AMotivoRefugo: string): TApontamento;
var
  LOperacao: TOperacaoOP;
begin
  if not (FStatus in OP_EM_ANDAMENTO) then
    raise EDominio.CreateFmt(
      'So e possivel apontar em OP liberada ou em producao (OP %s esta %s).',
      [FNumero, StatusOPDescr(FStatus)]);

  if (AQuantidadeBoa <= 0) and (AQuantidadeRefugo <= 0) then
    raise EDominio.Create('O apontamento precisa ter quantidade boa ou refugo.');

  LOperacao := OperacaoDaSequencia(ASequencia);
  if LOperacao = nil then
    raise EDominio.CreateFmt('A OP %s nao tem a operacao %d no roteiro.',
      [FNumero, ASequencia]);

  if (AQuantidadeRefugo > 0) and (Trim(AMotivoRefugo) = '') then
    raise EDominio.Create('Refugo apontado sem motivo: informe a causa.');

  Result := TApontamento.Create;
  Result.OrdemId := Id;
  Result.SequenciaOperacao := ASequencia;
  Result.QuantidadeBoa := AQuantidadeBoa;
  Result.QuantidadeRefugo := AQuantidadeRefugo;
  Result.TempoMinutos := ATempoMinutos;
  Result.Operador := AOperador;
  Result.MotivoRefugo := AMotivoRefugo;
  FApontamentos.Add(Result);

  // Acumula na operacao e na ordem.
  LOperacao.QuantidadeBoa := LOperacao.QuantidadeBoa + AQuantidadeBoa;
  LOperacao.QuantidadeRefugo := LOperacao.QuantidadeRefugo + AQuantidadeRefugo;
  LOperacao.TempoRealizadoMin := LOperacao.TempoRealizadoMin + ATempoMinutos;
  if LOperacao.Status = soPendente then
    LOperacao.Status := soEmExecucao;

  { Regra classica: so a ULTIMA operacao do roteiro entrega produto acabado.
    Apontar nas operacoes anteriores registra avanco, nao estoque. }
  if LOperacao.Sequencia = FOperacoes[FOperacoes.Count - 1].Sequencia then
  begin
    FQuantidadeProduzida := FQuantidadeProduzida + AQuantidadeBoa;
    FQuantidadeRefugada := FQuantidadeRefugada + AQuantidadeRefugo;
  end;

  if FStatus = opLiberada then
    MudarStatus(opEmProducao)
  else
    MarcarAtualizado;
end;

function TOrdemProducao.GetCustoPrevisto: Currency;
begin
  Result := FCustoMaterialPrevisto + FCustoOperacionalPrevisto;
end;

function TOrdemProducao.GetCustoReal: Currency;
begin
  Result := FCustoMaterialReal + FCustoOperacionalReal;
end;

function TOrdemProducao.GetCustoUnitarioReal: Currency;
begin
  if FQuantidadeProduzida <= 0 then
    Exit(0);
  Result := RoundTo(GetCustoReal / FQuantidadeProduzida, -4);
end;

function TOrdemProducao.GetSaldoAProduzir: Double;
begin
  Result := Max(0, FQuantidadePlanejada - FQuantidadeProduzida);
end;

function TOrdemProducao.GetPercentualConcluido: Double;
begin
  if FQuantidadePlanejada <= 0 then
    Exit(0);
  Result := Min(1, FQuantidadeProduzida / FQuantidadePlanejada);
end;

function TOrdemProducao.GetTempoPrevistoTotal: Double;
var
  LOperacao: TOperacaoOP;
begin
  Result := 0;
  for LOperacao in FOperacoes do
    Result := Result + LOperacao.TempoPrevistoMin;
end;

function TOrdemProducao.GetTempoRealizadoTotal: Double;
var
  LOperacao: TOperacaoOP;
begin
  Result := 0;
  for LOperacao in FOperacoes do
    Result := Result + LOperacao.TempoRealizadoMin;
end;

procedure TOrdemProducao.ValidarRegras(AErros: TList<string>);
begin
  inherited;
  if FComponentes.Count = 0 then
    AErros.Add('OP: nenhuma estrutura explodida (a lista de material esta vazia).');
  if FOperacoes.Count = 0 then
    AErros.Add('OP: nenhuma operacao no roteiro.');
end;

function TOrdemProducao.Clone: TEntidade;
var
  LCopia: TOrdemProducao;
  LComponente: TComponenteOP;
  LOperacao: TOperacaoOP;
  LApontamento: TApontamento;
begin
  Result := inherited Clone;
  LCopia := TOrdemProducao(Result);

  LCopia.FComponentes.Clear;
  for LComponente in FComponentes do
    LCopia.FComponentes.Add(TComponenteOP(LComponente.Clone));

  LCopia.FOperacoes.Clear;
  for LOperacao in FOperacoes do
    LCopia.FOperacoes.Add(TOperacaoOP(LOperacao.Clone));

  LCopia.FApontamentos.Clear;
  for LApontamento in FApontamentos do
    LCopia.FApontamentos.Add(TApontamento(LApontamento.Clone));
end;

function TOrdemProducao.ToJson: TJSONObject;
var
  LComponentes, LOperacoes, LApontamentos: TJSONArray;
  LComponente: TComponenteOP;
  LOperacao: TOperacaoOP;
  LApontamento: TApontamento;
begin
  Result := inherited ToJson;

  LComponentes := TJSONArray.Create;
  for LComponente in FComponentes do
    LComponentes.AddElement(LComponente.ToJson);
  Result.AddPair('Componentes', LComponentes);

  LOperacoes := TJSONArray.Create;
  for LOperacao in FOperacoes do
    LOperacoes.AddElement(LOperacao.ToJson);
  Result.AddPair('Operacoes', LOperacoes);

  LApontamentos := TJSONArray.Create;
  for LApontamento in FApontamentos do
    LApontamentos.AddElement(LApontamento.ToJson);
  Result.AddPair('Apontamentos', LApontamentos);
end;

procedure TOrdemProducao.FromJson(AJson: TJSONObject);

  procedure CarregarLista(const ANome: string; const ACriar: TFunc<TEntidade>;
    const AAdicionar: TProc<TEntidade>);
  var
    LValor: TJSONValue;
    LElemento: TJSONValue;
    LFilho: TEntidade;
  begin
    LValor := AJson.GetValue(ANome);
    if not (LValor is TJSONArray) then
      Exit;
    for LElemento in TJSONArray(LValor) do
      if LElemento is TJSONObject then
      begin
        LFilho := ACriar();
        try
          LFilho.FromJson(TJSONObject(LElemento));
          AAdicionar(LFilho);
        except
          LFilho.Free;
          raise;
        end;
      end;
  end;

begin
  inherited FromJson(AJson);
  FComponentes.Clear;
  FOperacoes.Clear;
  FApontamentos.Clear;

  CarregarLista('Componentes',
    function: TEntidade
    begin
      Result := TComponenteOP.Create;
    end,
    procedure(AFilho: TEntidade)
    begin
      FComponentes.Add(TComponenteOP(AFilho));
    end);

  CarregarLista('Operacoes',
    function: TEntidade
    begin
      Result := TOperacaoOP.Create;
    end,
    procedure(AFilho: TEntidade)
    begin
      FOperacoes.Add(TOperacaoOP(AFilho));
    end);

  CarregarLista('Apontamentos',
    function: TEntidade
    begin
      Result := TApontamento.Create;
    end,
    procedure(AFilho: TEntidade)
    begin
      FApontamentos.Add(TApontamento(AFilho));
    end);
end;

function TOrdemProducao.Resumo: string;
begin
  Result := Format('#%d %s %-12s %-24s %9.2f/%9.2f %-12s',
    [Id, FNumero, FCodigoProduto, Copy(FDescricaoProduto, 1, 24),
     FQuantidadeProduzida, FQuantidadePlanejada, StatusOPDescr(FStatus)]);
end;

{ TLinhaExplosao }

function TLinhaExplosao.Indentado: string;
begin
  Result := StringOfChar(' ', Nivel * 3) + Codigo;
end;

end.
