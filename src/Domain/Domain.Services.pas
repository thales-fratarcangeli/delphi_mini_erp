{*******************************************************************************
  Domain.Services

  Onde moram as regras que envolvem MAIS DE UMA entidade (por isso nao cabem
  dentro de TPedido ou TProduto sozinhos).

  ESTUDO - conceitos demonstrados aqui:
    * STRATEGY: IPoliticaDesconto - a regra de desconto e trocavel em runtime
    * COMPOSITE + STRATEGY: TPoliticaMelhorDesconto avalia varias e escolhe
    * Injecao de dependencia por CONSTRUTOR (tudo que o servico usa chega
      pronto como interface; o servico nao cria nada de infraestrutura)
    * Unit of Work para consistencia: ou tudo acontece, ou nada acontece
    * Eventos de dominio para efeitos colaterais (avisos, e-mails, logs)
    * TResultado<T> para falhas ESPERADAS (sem estoque, sem credito) e
      excecoes para falhas INESPERADAS (id inexistente, estado impossivel)
*******************************************************************************}
unit Domain.Services;

interface

uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  Core.Types,
  Core.Logger,
  Core.Events,
  Domain.Entities,
  Domain.Enums,
  Domain.Events,
  Domain.Interfaces,
  Domain.Specifications;

type
  { ==========================================================================
    STRATEGY: politicas de desconto
    ========================================================================== }
  IPoliticaDesconto = interface
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D20}']
    function Nome: string;
    /// Valor (em R$) de desconto a conceder sobre o total bruto do pedido.
    function Calcular(APedido: TPedido; ACliente: TCliente): Currency;
  end;

  TPoliticaSemDesconto = class(TInterfacedObject, IPoliticaDesconto)
  public
    function Nome: string;
    function Calcular(APedido: TPedido; ACliente: TCliente): Currency;
  end;

  /// Desconto conforme a categoria do cliente (Prata 3%, Ouro 6%, VIP 10%).
  TPoliticaCategoria = class(TInterfacedObject, IPoliticaDesconto)
  public
    function Nome: string;
    function Calcular(APedido: TPedido; ACliente: TCliente): Currency;
  end;

  /// Desconto por volume: a partir de N pecas, aplica um percentual.
  TPoliticaVolume = class(TInterfacedObject, IPoliticaDesconto)
  private
    FPecasMinimas: Integer;
    FPercentual: Double;
  public
    constructor Create(APecasMinimas: Integer; APercentual: Double);
    function Nome: string;
    function Calcular(APedido: TPedido; ACliente: TCliente): Currency;
  end;

  /// Desconto por valor do pedido: acima de X reais, aplica um percentual.
  TPoliticaValor = class(TInterfacedObject, IPoliticaDesconto)
  private
    FValorMinimo: Currency;
    FPercentual: Double;
  public
    constructor Create(AValorMinimo: Currency; APercentual: Double);
    function Nome: string;
    function Calcular(APedido: TPedido; ACliente: TCliente): Currency;
  end;

  /// COMPOSITE: avalia todas as politicas e devolve a MAIS vantajosa
  /// para o cliente (nao acumula descontos).
  TPoliticaMelhorDesconto = class(TInterfacedObject, IPoliticaDesconto)
  private
    FPoliticas: TList<IPoliticaDesconto>;
    FUltimaEscolhida: string;
  public
    constructor Create(const APoliticas: array of IPoliticaDesconto);
    destructor Destroy; override;
    function Nome: string;
    function Calcular(APedido: TPedido; ACliente: TCliente): Currency;
    property UltimaEscolhida: string read FUltimaEscolhida;
  end;

  { ==========================================================================
    SERVICO DE ESTOQUE
    ========================================================================== }
  IServicoEstoque = interface
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D21}']
    procedure RegistrarEntrada(AProdutoId, AQuantidade: Integer;
      const AMotivo: string);
    procedure AjustarInventario(AProdutoId, ANovoSaldo: Integer;
      const AMotivo: string);
    /// Lista os problemas de disponibilidade (vazio = tudo disponivel).
    function ProblemasDeDisponibilidade(APedido: TPedido): TArray<string>;
    procedure ReservarParaPedido(APedido: TPedido);
    procedure DevolverDoPedido(APedido: TPedido; const AMotivo: string);
    function ValorTotalEmEstoque: Currency;

    // ---------------- movimentos de chao de fabrica ----------------
    /// Baixa de componente requisitado por uma ordem de producao.
    procedure RequisitarParaOrdem(AProdutoId, AQuantidade, AOrdemId: Integer;
      const AMotivo: string);
    /// Devolucao de componente ao almoxarifado (cancelamento/sobra).
    procedure DevolverDaOrdem(AProdutoId, AQuantidade, AOrdemId: Integer;
      const AMotivo: string);
    /// Entrada do item fabricado; atualiza o custo medio movel.
    procedure EntradaDeProducao(AProdutoId, AQuantidade, AOrdemId: Integer;
      ACustoUnitario: Currency; const AMotivo: string);
    /// Entrada de compra com custo: tambem recalcula o custo medio.
    procedure EntradaComCusto(AProdutoId, AQuantidade: Integer;
      ACustoUnitario: Currency; const AMotivo: string);
  end;

  TServicoEstoque = class(TInterfacedObject, IServicoEstoque)
  private
    FProdutos: IRepositorioProdutos;
    FMovimentos: IRepositorioMovimentos;
    FEventos: IEventBus;
    FLogger: ILogger;
    FUoW: IUnitOfWork;
    procedure Movimentar(AProduto: TProduto; ATipo: TTipoMovimento;
      AQuantidade: Integer; const AMotivo: string; APedidoId: Integer;
      AOrdemId: Integer = 0; ACustoUnitario: Currency = 0);
    procedure AvisarSeEstoqueBaixo(AProduto: TProduto);
  public
    constructor Create(const AProdutos: IRepositorioProdutos;
      const AMovimentos: IRepositorioMovimentos; const AEventos: IEventBus;
      const ALogger: ILogger; const AUoW: IUnitOfWork);

    procedure RegistrarEntrada(AProdutoId, AQuantidade: Integer;
      const AMotivo: string);
    procedure AjustarInventario(AProdutoId, ANovoSaldo: Integer;
      const AMotivo: string);
    function ProblemasDeDisponibilidade(APedido: TPedido): TArray<string>;
    procedure ReservarParaPedido(APedido: TPedido);
    procedure DevolverDoPedido(APedido: TPedido; const AMotivo: string);
    function ValorTotalEmEstoque: Currency;
    procedure RequisitarParaOrdem(AProdutoId, AQuantidade, AOrdemId: Integer;
      const AMotivo: string);
    procedure DevolverDaOrdem(AProdutoId, AQuantidade, AOrdemId: Integer;
      const AMotivo: string);
    procedure EntradaDeProducao(AProdutoId, AQuantidade, AOrdemId: Integer;
      ACustoUnitario: Currency; const AMotivo: string);
    procedure EntradaComCusto(AProdutoId, AQuantidade: Integer;
      ACustoUnitario: Currency; const AMotivo: string);
  end;

  { ==========================================================================
    SERVICO DE VENDAS - orquestra o ciclo de vida do pedido
    ========================================================================== }
  IServicoVendas = interface
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D22}']
    function CriarPedido(AClienteId: Integer): TPedido;
    procedure AdicionarItem(APedidoId, AProdutoId, AQuantidade: Integer;
      ADescontoItem: Double = 0);
    procedure RemoverItem(APedidoId, AIndiceItem: Integer);
    function ConfirmarPedido(APedidoId: Integer): TResultado<Currency>;
    function PagarPedido(APedidoId: Integer;
      AForma: TFormaPagamento): TResultado<string>;
    procedure EnviarPedido(APedidoId: Integer);
    procedure EntregarPedido(APedidoId: Integer);
    procedure CancelarPedido(APedidoId: Integer; const AMotivo: string);
    /// Quanto o cliente ainda pode comprar a prazo.
    function CreditoDisponivel(AClienteId: Integer): Currency;
  end;

  TServicoVendas = class(TInterfacedObject, IServicoVendas)
  private
    FPedidos: IRepositorioPedidos;
    FClientes: IRepositorioClientes;
    FProdutos: IRepositorioProdutos;
    FPagamentos: IRepositorioPagamentos;
    FEstoque: IServicoEstoque;
    FPolitica: IPoliticaDesconto;
    FGateway: IGatewayPagamento;
    FEventos: IEventBus;
    FLogger: ILogger;
    FUoW: IUnitOfWork;
    function ObterPedido(APedidoId: Integer): TPedido;
    function ObterCliente(AClienteId: Integer): TCliente;
  public
    constructor Create(const APedidos: IRepositorioPedidos;
      const AClientes: IRepositorioClientes;
      const AProdutos: IRepositorioProdutos;
      const APagamentos: IRepositorioPagamentos;
      const AEstoque: IServicoEstoque; const APolitica: IPoliticaDesconto;
      const AGateway: IGatewayPagamento; const AEventos: IEventBus;
      const ALogger: ILogger; const AUoW: IUnitOfWork);

    function CriarPedido(AClienteId: Integer): TPedido;
    procedure AdicionarItem(APedidoId, AProdutoId, AQuantidade: Integer;
      ADescontoItem: Double = 0);
    procedure RemoverItem(APedidoId, AIndiceItem: Integer);
    function ConfirmarPedido(APedidoId: Integer): TResultado<Currency>;
    function PagarPedido(APedidoId: Integer;
      AForma: TFormaPagamento): TResultado<string>;
    procedure EnviarPedido(APedidoId: Integer);
    procedure EntregarPedido(APedidoId: Integer);
    procedure CancelarPedido(APedidoId: Integer; const AMotivo: string);
    function CreditoDisponivel(AClienteId: Integer): Currency;
  end;

implementation

{ TPoliticaSemDesconto }

function TPoliticaSemDesconto.Nome: string;
begin
  Result := 'Sem desconto';
end;

function TPoliticaSemDesconto.Calcular(APedido: TPedido; ACliente: TCliente): Currency;
begin
  Result := 0;
end;

{ TPoliticaCategoria }

function TPoliticaCategoria.Nome: string;
begin
  Result := 'Desconto por categoria do cliente';
end;

function TPoliticaCategoria.Calcular(APedido: TPedido; ACliente: TCliente): Currency;
begin
  if (APedido = nil) or (ACliente = nil) then
    Exit(0);
  Result := RoundTo(APedido.TotalBruto * ACliente.DescontoCategoria, -2);
end;

{ TPoliticaVolume }

constructor TPoliticaVolume.Create(APecasMinimas: Integer; APercentual: Double);
begin
  inherited Create;
  FPecasMinimas := APecasMinimas;
  FPercentual := APercentual;
end;

function TPoliticaVolume.Nome: string;
begin
  Result := Format('Desconto por volume (%d+ pecas = %.0f%%)',
    [FPecasMinimas, FPercentual * 100]);
end;

function TPoliticaVolume.Calcular(APedido: TPedido; ACliente: TCliente): Currency;
begin
  if (APedido = nil) or (APedido.QuantidadeItens < FPecasMinimas) then
    Exit(0);
  Result := RoundTo(APedido.TotalBruto * FPercentual, -2);
end;

{ TPoliticaValor }

constructor TPoliticaValor.Create(AValorMinimo: Currency; APercentual: Double);
begin
  inherited Create;
  FValorMinimo := AValorMinimo;
  FPercentual := APercentual;
end;

function TPoliticaValor.Nome: string;
begin
  Result := Format('Desconto por valor (acima de %s = %.0f%%)',
    [TFmt.Moeda(FValorMinimo), FPercentual * 100]);
end;

function TPoliticaValor.Calcular(APedido: TPedido; ACliente: TCliente): Currency;
begin
  if (APedido = nil) or (APedido.TotalBruto < FValorMinimo) then
    Exit(0);
  Result := RoundTo(APedido.TotalBruto * FPercentual, -2);
end;

{ TPoliticaMelhorDesconto }

constructor TPoliticaMelhorDesconto.Create(const APoliticas: array of IPoliticaDesconto);
var
  LPolitica: IPoliticaDesconto;
begin
  inherited Create;
  FPoliticas := TList<IPoliticaDesconto>.Create;
  for LPolitica in APoliticas do
    FPoliticas.Add(LPolitica);
end;

destructor TPoliticaMelhorDesconto.Destroy;
begin
  FPoliticas.Free;
  inherited;
end;

function TPoliticaMelhorDesconto.Nome: string;
begin
  Result := 'Melhor desconto entre as politicas cadastradas';
end;

function TPoliticaMelhorDesconto.Calcular(APedido: TPedido; ACliente: TCliente): Currency;
var
  LPolitica: IPoliticaDesconto;
  LValor: Currency;
begin
  Result := 0;
  FUltimaEscolhida := 'nenhuma';
  for LPolitica in FPoliticas do
  begin
    LValor := LPolitica.Calcular(APedido, ACliente);
    if LValor > Result then
    begin
      Result := LValor;
      FUltimaEscolhida := LPolitica.Nome;
    end;
  end;
end;

{ TServicoEstoque }

constructor TServicoEstoque.Create(const AProdutos: IRepositorioProdutos;
  const AMovimentos: IRepositorioMovimentos; const AEventos: IEventBus;
  const ALogger: ILogger; const AUoW: IUnitOfWork);
begin
  inherited Create;
  FProdutos := AProdutos;
  FMovimentos := AMovimentos;
  FEventos := AEventos;
  FLogger := ALogger;
  FUoW := AUoW;
end;

procedure TServicoEstoque.AvisarSeEstoqueBaixo(AProduto: TProduto);
begin
  if AProduto.AbaixoDoMinimo then
    FEventos.Publicar(TEstoqueBaixo.Create(AProduto.Id, AProduto.Codigo,
      AProduto.Descricao, AProduto.Estoque, AProduto.EstoqueMinimo));
end;

procedure TServicoEstoque.Movimentar(AProduto: TProduto; ATipo: TTipoMovimento;
  AQuantidade: Integer; const AMotivo: string; APedidoId: Integer;
  AOrdemId: Integer; ACustoUnitario: Currency);
var
  LMovimento: TMovimentoEstoque;
  LSaldoAnterior: Integer;
  LCustoAnterior: Currency;
  LProduto: TProduto;
begin
  LSaldoAnterior := AProduto.Estoque;
  LCustoAnterior := AProduto.CustoMedio;

  { CUSTO MEDIO MOVEL: precisa ser recalculado ANTES de o saldo mudar,
    porque a media pondera o saldo ANTIGO com o que esta entrando. }
  if MovimentoEhEntrada(ATipo) and (ACustoUnitario > 0) then
    AProduto.AtualizarCustoMedio(AQuantidade, ACustoUnitario);

  AProduto.MovimentarEstoque(ATipo, AQuantidade);
  FProdutos.Atualizar(AProduto);

  // COMPENSACAO: se a transacao falhar depois daqui, o saldo volta ao que era.
  LProduto := AProduto;
  FUoW.RegistrarDesfazer(
    procedure
    begin
      LProduto.Estoque := LSaldoAnterior;
      LProduto.CustoMedio := LCustoAnterior;  // o custo medio tambem volta
    end,
    Format('restaurar estoque de %s para %d', [AProduto.Codigo, LSaldoAnterior]));

  LMovimento := TMovimentoEstoque.Create;
  LMovimento.ProdutoId := AProduto.Id;
  LMovimento.CodigoProduto := AProduto.Codigo;
  LMovimento.Tipo := ATipo;
  LMovimento.Quantidade := AQuantidade;
  LMovimento.SaldoResultante := AProduto.Estoque;
  LMovimento.Motivo := AMotivo;
  LMovimento.PedidoId := APedidoId;
  LMovimento.OrdemProducaoId := AOrdemId;
  if ACustoUnitario > 0 then
    LMovimento.CustoUnitario := ACustoUnitario
  else
    LMovimento.CustoUnitario := AProduto.CustoMedio;
  FMovimentos.Adicionar(LMovimento);

  FLogger.Debug('Estoque %s: %s %d un. (saldo %d -> %d)',
    [AProduto.Codigo, TipoMovimentoDescr(ATipo), AQuantidade,
     LSaldoAnterior, AProduto.Estoque]);

  AvisarSeEstoqueBaixo(AProduto);
end;

procedure TServicoEstoque.RegistrarEntrada(AProdutoId, AQuantidade: Integer;
  const AMotivo: string);
var
  LProduto: TProduto;
begin
  LProduto := FProdutos.PorId(AProdutoId);
  FUoW.Executar(
    procedure
    begin
      Movimentar(LProduto, tmEntrada, AQuantidade, AMotivo, 0);
    end);
end;

procedure TServicoEstoque.AjustarInventario(AProdutoId, ANovoSaldo: Integer;
  const AMotivo: string);
var
  LProduto: TProduto;
begin
  if ANovoSaldo < 0 then
    raise EDominio.Create('O saldo ajustado nao pode ser negativo.');
  LProduto := FProdutos.PorId(AProdutoId);
  FUoW.Executar(
    procedure
    begin
      Movimentar(LProduto, tmAjuste, ANovoSaldo, AMotivo, 0);
    end);
end;

function TServicoEstoque.ProblemasDeDisponibilidade(APedido: TPedido): TArray<string>;
var
  LItem: TItemPedido;
  LProduto: TProduto;
  LProblemas: TList<string>;
begin
  LProblemas := TList<string>.Create;
  try
    for LItem in APedido.Itens do
    begin
      if not FProdutos.TentarPorId(LItem.ProdutoId, LProduto) then
      begin
        LProblemas.Add(Format('Produto %d nao existe mais no cadastro.',
          [LItem.ProdutoId]));
        Continue;
      end;
      if not LProduto.Ativo then
        LProblemas.Add(Format('Produto %s esta inativo.', [LProduto.Codigo]))
      else if not LProduto.TemEstoquePara(LItem.Quantidade) then
        LProblemas.Add(Format('Produto %s: estoque %d, pedido %d.',
          [LProduto.Codigo, LProduto.Estoque, LItem.Quantidade]));
    end;
    Result := LProblemas.ToArray;
  finally
    LProblemas.Free;
  end;
end;

procedure TServicoEstoque.ReservarParaPedido(APedido: TPedido);
var
  LItem: TItemPedido;
begin
  for LItem in APedido.Itens do
    Movimentar(FProdutos.PorId(LItem.ProdutoId), tmSaida, LItem.Quantidade,
      Format('Reserva do pedido %s', [APedido.Numero]), APedido.Id);
end;

procedure TServicoEstoque.DevolverDoPedido(APedido: TPedido; const AMotivo: string);
var
  LItem: TItemPedido;
  LProduto: TProduto;
begin
  for LItem in APedido.Itens do
    if FProdutos.TentarPorId(LItem.ProdutoId, LProduto) then
      Movimentar(LProduto, tmEntrada, LItem.Quantidade, AMotivo, APedido.Id);
end;

function TServicoEstoque.ValorTotalEmEstoque: Currency;
var
  LProduto: TProduto;
begin
  Result := 0;
  for LProduto in FProdutos.Todos do
    Result := Result + LProduto.ValorEmEstoque;
end;

{ ---------------------- movimentos de chao de fabrica ---------------------- }

procedure TServicoEstoque.RequisitarParaOrdem(AProdutoId, AQuantidade,
  AOrdemId: Integer; const AMotivo: string);
var
  LProduto: TProduto;
begin
  LProduto := FProdutos.PorId(AProdutoId);
  Movimentar(LProduto, tmConsumo, AQuantidade, AMotivo, 0, AOrdemId,
    LProduto.CustoMedio);
end;

procedure TServicoEstoque.DevolverDaOrdem(AProdutoId, AQuantidade,
  AOrdemId: Integer; const AMotivo: string);
var
  LProduto: TProduto;
begin
  LProduto := FProdutos.PorId(AProdutoId);
  { Devolucao entra pelo MESMO custo medio atual: nao inventamos custo novo
    ao devolver material que ja estava valorizado. }
  Movimentar(LProduto, tmEntrada, AQuantidade, AMotivo, 0, AOrdemId, 0);
end;

procedure TServicoEstoque.EntradaDeProducao(AProdutoId, AQuantidade,
  AOrdemId: Integer; ACustoUnitario: Currency; const AMotivo: string);
var
  LProduto: TProduto;
begin
  LProduto := FProdutos.PorId(AProdutoId);
  Movimentar(LProduto, tmProducao, AQuantidade, AMotivo, 0, AOrdemId,
    ACustoUnitario);
end;

procedure TServicoEstoque.EntradaComCusto(AProdutoId, AQuantidade: Integer;
  ACustoUnitario: Currency; const AMotivo: string);
var
  LProduto: TProduto;
begin
  LProduto := FProdutos.PorId(AProdutoId);
  FUoW.Executar(
    procedure
    begin
      Movimentar(LProduto, tmEntrada, AQuantidade, AMotivo, 0, 0, ACustoUnitario);
    end);
end;

{ TServicoVendas }

constructor TServicoVendas.Create(const APedidos: IRepositorioPedidos;
  const AClientes: IRepositorioClientes; const AProdutos: IRepositorioProdutos;
  const APagamentos: IRepositorioPagamentos; const AEstoque: IServicoEstoque;
  const APolitica: IPoliticaDesconto; const AGateway: IGatewayPagamento;
  const AEventos: IEventBus; const ALogger: ILogger; const AUoW: IUnitOfWork);
begin
  inherited Create;
  FPedidos := APedidos;
  FClientes := AClientes;
  FProdutos := AProdutos;
  FPagamentos := APagamentos;
  FEstoque := AEstoque;
  FPolitica := APolitica;
  FGateway := AGateway;
  FEventos := AEventos;
  FLogger := ALogger;
  FUoW := AUoW;
end;

function TServicoVendas.ObterPedido(APedidoId: Integer): TPedido;
begin
  Result := FPedidos.PorId(APedidoId);
end;

function TServicoVendas.ObterCliente(AClienteId: Integer): TCliente;
begin
  Result := FClientes.PorId(AClienteId);
end;

function TServicoVendas.CriarPedido(AClienteId: Integer): TPedido;
var
  LCliente: TCliente;
  LPedido: TPedido;
begin
  LCliente := ObterCliente(AClienteId);
  if not LCliente.Ativo then
    raise EDominio.CreateFmt('O cliente %s esta inativo.', [LCliente.Nome]);

  LPedido := TPedido.Create;
  try
    LPedido.Numero := FPedidos.ProximoNumero;
    LPedido.ClienteId := LCliente.Id;
    LPedido.NomeCliente := LCliente.Nome;
    Result := FPedidos.Adicionar(LPedido); // repositorio assume a posse
  except
    LPedido.Free;
    raise;
  end;

  FLogger.Info('Pedido %s criado para %s', [Result.Numero, LCliente.Nome]);
end;

procedure TServicoVendas.AdicionarItem(APedidoId, AProdutoId,
  AQuantidade: Integer; ADescontoItem: Double);
var
  LPedido: TPedido;
  LProduto: TProduto;
begin
  LPedido := ObterPedido(APedidoId);
  LProduto := FProdutos.PorId(AProdutoId);
  LPedido.AdicionarItem(LProduto, AQuantidade, ADescontoItem);
  FPedidos.Atualizar(LPedido);
  FLogger.Debug('Pedido %s: +%d x %s', [LPedido.Numero, AQuantidade, LProduto.Codigo]);
end;

procedure TServicoVendas.RemoverItem(APedidoId, AIndiceItem: Integer);
var
  LPedido: TPedido;
begin
  LPedido := ObterPedido(APedidoId);
  LPedido.RemoverItem(AIndiceItem);
  FPedidos.Atualizar(LPedido);
end;

function TServicoVendas.CreditoDisponivel(AClienteId: Integer): Currency;
var
  LCliente: TCliente;
begin
  LCliente := ObterCliente(AClienteId);
  Result := LCliente.LimiteCredito - FPedidos.TotalEmAbertoDoCliente(AClienteId);
  if Result < 0 then
    Result := 0;
end;

function TServicoVendas.ConfirmarPedido(APedidoId: Integer): TResultado<Currency>;
var
  LPedido: TPedido;
  LCliente: TCliente;
  LProblemas: TArray<string>;
  LDesconto: Currency;
  LTotal: Currency;
  LDisponivel: Currency;
begin
  LPedido := ObterPedido(APedidoId);

  if LPedido.Status <> spRascunho then
    Exit(TResultado<Currency>.FalhaFmt(
      'O pedido %s ja foi confirmado (status atual: %s).',
      [LPedido.Numero, StatusPedidoDescr(LPedido.Status)]));

  // 1) o pedido faz sentido por si so?
  LProblemas := LPedido.Erros;
  if Length(LProblemas) > 0 then
    Exit(TResultado<Currency>.Falha(string.Join('; ', LProblemas)));

  LCliente := ObterCliente(LPedido.ClienteId);
  if not LCliente.Ativo then
    Exit(TResultado<Currency>.FalhaFmt('Cliente %s inativo.', [LCliente.Nome]));

  // 2) tem estoque para todos os itens?
  LProblemas := FEstoque.ProblemasDeDisponibilidade(LPedido);
  if Length(LProblemas) > 0 then
    Exit(TResultado<Currency>.Falha('Estoque insuficiente: ' +
      string.Join(' ', LProblemas)));

  // 3) aplica a politica de desconto vigente (STRATEGY)
  LDesconto := FPolitica.Calcular(LPedido, LCliente);
  LPedido.DescontoNegociado := LDesconto;
  LTotal := LPedido.TotalLiquido;

  // 4) o cliente tem credito?
  LDisponivel := CreditoDisponivel(LCliente.Id);
  if LTotal > LDisponivel then
  begin
    FEventos.Publicar(TLimiteCreditoExcedido.Create(LCliente.Id, LCliente.Nome,
      LDisponivel, LTotal));
    LPedido.DescontoNegociado := 0; // desfaz o desconto especulativo
    Exit(TResultado<Currency>.FalhaFmt(
      'Credito insuficiente: disponivel %s, pedido %s.',
      [TFmt.Moeda(LDisponivel), TFmt.Moeda(LTotal)]));
  end;

  // 5) ponto sem volta: baixa de estoque + mudanca de status, tudo ou nada
  FUoW.Executar(
    procedure
    begin
      FEstoque.ReservarParaPedido(LPedido);
      LPedido.MudarStatus(spConfirmado);
      FPedidos.Atualizar(LPedido);
    end);

  FEventos.Publicar(TPedidoConfirmado.Create(LPedido.Id, LPedido.Numero,
    LCliente.Id, LTotal));

  Result := TResultado<Currency>.Ok(LTotal);
end;

function TServicoVendas.PagarPedido(APedidoId: Integer;
  AForma: TFormaPagamento): TResultado<string>;
var
  LPedido: TPedido;
  LPagamento: TPagamento;
  LAutorizacao: string;
  LAprovado: Boolean;
begin
  LPedido := ObterPedido(APedidoId);

  if not LPedido.PodeMudarPara(spPago) then
    Exit(TResultado<string>.FalhaFmt(
      'O pedido %s nao pode ser pago no status %s.',
      [LPedido.Numero, StatusPedidoDescr(LPedido.Status)]));

  LAprovado := FGateway.Autorizar(LPedido.TotalLiquido, AForma, LAutorizacao);

  LPagamento := TPagamento.Create;
  try
    LPagamento.PedidoId := LPedido.Id;
    LPagamento.Valor := LPedido.TotalLiquido;
    LPagamento.Forma := AForma;
    LPagamento.Autorizado := LAprovado;
    LPagamento.Autorizacao := LAutorizacao;
    FPagamentos.Adicionar(LPagamento);
  except
    LPagamento.Free;
    raise;
  end;

  if not LAprovado then
  begin
    FLogger.Aviso('Pagamento recusado para o pedido %s (%s)',
      [LPedido.Numero, LAutorizacao]);
    Exit(TResultado<string>.FalhaFmt('Pagamento recusado pelo %s: %s.',
      [FGateway.Nome, LAutorizacao]));
  end;

  FUoW.Executar(
    procedure
    begin
      LPedido.FormaPagamento := AForma;
      LPedido.MudarStatus(spPago);
      FPedidos.Atualizar(LPedido);
    end);

  FEventos.Publicar(TPagamentoAprovado.Create(LPedido.Id,
    LPagamento.Valor, AForma));

  Result := TResultado<string>.Ok(LAutorizacao);
end;

procedure TServicoVendas.EnviarPedido(APedidoId: Integer);
var
  LPedido: TPedido;
begin
  LPedido := ObterPedido(APedidoId);
  LPedido.MudarStatus(spEnviado);   // a propria entidade valida a transicao
  FPedidos.Atualizar(LPedido);
  FLogger.Info('Pedido %s enviado.', [LPedido.Numero]);
end;

procedure TServicoVendas.EntregarPedido(APedidoId: Integer);
var
  LPedido: TPedido;
begin
  LPedido := ObterPedido(APedidoId);
  LPedido.MudarStatus(spEntregue);
  FPedidos.Atualizar(LPedido);
  FLogger.Info('Pedido %s entregue.', [LPedido.Numero]);
end;

procedure TServicoVendas.CancelarPedido(APedidoId: Integer; const AMotivo: string);
var
  LPedido: TPedido;
  LStatusAnterior: TStatusPedido;
begin
  LPedido := ObterPedido(APedidoId);
  LStatusAnterior := LPedido.Status;

  if not LPedido.PodeMudarPara(spCancelado) then
    raise EDominio.CreateFmt('O pedido %s (%s) nao pode mais ser cancelado.',
      [LPedido.Numero, StatusPedidoDescr(LStatusAnterior)]);

  FUoW.Executar(
    procedure
    begin
      // Se o pedido segurava estoque, devolve tudo antes de encerrar.
      if LPedido.ReservaEstoque then
        FEstoque.DevolverDoPedido(LPedido,
          Format('Cancelamento do pedido %s', [LPedido.Numero]));
      LPedido.MudarStatus(spCancelado);
      LPedido.Observacao := Copy(Trim(LPedido.Observacao + ' [CANCELADO: ' +
        AMotivo + ']'), 1, 200);
      FPedidos.Atualizar(LPedido);
    end);

  FEventos.Publicar(TPedidoCancelado.Create(LPedido.Id, LPedido.Numero,
    AMotivo, LStatusAnterior));
end;

end.
