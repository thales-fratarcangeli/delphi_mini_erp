{*******************************************************************************
  Domain.Events

  Eventos de dominio: "algo relevante para o negocio aconteceu".

  ESTUDO:
    * Eventos sao objetos IMUTAVEIS (so leitura) que descrevem um fato passado
      -> por isso os nomes estao no participio: Confirmado, Cancelado, Aprovado
    * Quem publica nao sabe (e nao quer saber) quem vai reagir. Adicionar um
      novo comportamento = assinar o evento, sem tocar no servico existente.
      Isso e o "O" de SOLID (aberto para extensao, fechado para modificacao).
*******************************************************************************}
unit Domain.Events;

interface

uses
  System.SysUtils,
  Core.Events,
  Core.Types,
  Domain.Enums;

type
  TPedidoConfirmado = class(TEventoDominio)
  private
    FPedidoId: Integer;
    FNumero: string;
    FClienteId: Integer;
    FTotal: Currency;
  public
    constructor Create(APedidoId: Integer; const ANumero: string;
      AClienteId: Integer; ATotal: Currency); reintroduce;
    function Descricao: string; override;
    property PedidoId: Integer read FPedidoId;
    property Numero: string read FNumero;
    property ClienteId: Integer read FClienteId;
    property Total: Currency read FTotal;
  end;

  TPedidoCancelado = class(TEventoDominio)
  private
    FPedidoId: Integer;
    FNumero: string;
    FMotivo: string;
    FStatusAnterior: TStatusPedido;
  public
    constructor Create(APedidoId: Integer; const ANumero, AMotivo: string;
      AStatusAnterior: TStatusPedido); reintroduce;
    function Descricao: string; override;
    property PedidoId: Integer read FPedidoId;
    property Numero: string read FNumero;
    property Motivo: string read FMotivo;
    property StatusAnterior: TStatusPedido read FStatusAnterior;
  end;

  TEstoqueBaixo = class(TEventoDominio)
  private
    FProdutoId: Integer;
    FCodigo: string;
    FDescricao: string;
    FSaldo: Integer;
    FMinimo: Integer;
  public
    constructor Create(AProdutoId: Integer; const ACodigo, ADescricao: string;
      ASaldo, AMinimo: Integer); reintroduce;
    function Descricao: string; override;
    property ProdutoId: Integer read FProdutoId;
    property Codigo: string read FCodigo;
    property DescricaoProduto: string read FDescricao;
    property Saldo: Integer read FSaldo;
    property Minimo: Integer read FMinimo;
  end;

  TPagamentoAprovado = class(TEventoDominio)
  private
    FPedidoId: Integer;
    FValor: Currency;
    FForma: TFormaPagamento;
  public
    constructor Create(APedidoId: Integer; AValor: Currency;
      AForma: TFormaPagamento); reintroduce;
    function Descricao: string; override;
    property PedidoId: Integer read FPedidoId;
    property Valor: Currency read FValor;
    property Forma: TFormaPagamento read FForma;
  end;

  TLimiteCreditoExcedido = class(TEventoDominio)
  private
    FClienteId: Integer;
    FNomeCliente: string;
    FLimite: Currency;
    FSolicitado: Currency;
  public
    constructor Create(AClienteId: Integer; const ANomeCliente: string;
      ALimite, ASolicitado: Currency); reintroduce;
    function Descricao: string; override;
    property ClienteId: Integer read FClienteId;
    property NomeCliente: string read FNomeCliente;
    property Limite: Currency read FLimite;
    property Solicitado: Currency read FSolicitado;
  end;

  { ==========================================================================
    EVENTOS DO CHAO DE FABRICA
    ========================================================================== }

  TOrdemLiberada = class(TEventoDominio)
  private
    FOrdemId: Integer;
    FNumero: string;
    FCodigoProduto: string;
    FQuantidade: Double;
    FCustoMaterial: Currency;
  public
    constructor Create(AOrdemId: Integer; const ANumero, ACodigoProduto: string;
      AQuantidade: Double; ACustoMaterial: Currency); reintroduce;
    function Descricao: string; override;
    property OrdemId: Integer read FOrdemId;
    property Numero: string read FNumero;
    property CodigoProduto: string read FCodigoProduto;
    property Quantidade: Double read FQuantidade;
    property CustoMaterial: Currency read FCustoMaterial;
  end;

  TApontamentoRegistrado = class(TEventoDominio)
  private
    FOrdemId: Integer;
    FNumero: string;
    FSequencia: Integer;
    FQuantidadeBoa: Double;
    FQuantidadeRefugo: Double;
    FOperador: string;
  public
    constructor Create(AOrdemId: Integer; const ANumero: string;
      ASequencia: Integer; AQuantidadeBoa, AQuantidadeRefugo: Double;
      const AOperador: string); reintroduce;
    function Descricao: string; override;
    property OrdemId: Integer read FOrdemId;
    property Numero: string read FNumero;
    property Sequencia: Integer read FSequencia;
    property QuantidadeBoa: Double read FQuantidadeBoa;
    property QuantidadeRefugo: Double read FQuantidadeRefugo;
    property Operador: string read FOperador;
  end;

  TOrdemConcluida = class(TEventoDominio)
  private
    FOrdemId: Integer;
    FNumero: string;
    FQuantidadeProduzida: Double;
    FQuantidadeRefugada: Double;
    FVariacaoCusto: Currency;
  public
    constructor Create(AOrdemId: Integer; const ANumero: string;
      AQuantidadeProduzida, AQuantidadeRefugada: Double;
      AVariacaoCusto: Currency); reintroduce;
    function Descricao: string; override;
    property OrdemId: Integer read FOrdemId;
    property Numero: string read FNumero;
    property QuantidadeProduzida: Double read FQuantidadeProduzida;
    property QuantidadeRefugada: Double read FQuantidadeRefugada;
    property VariacaoCusto: Currency read FVariacaoCusto;
  end;

  /// Publicado quando uma OP nao pode ser liberada por falta de componente.
  TFaltaDeMaterial = class(TEventoDominio)
  private
    FOrdemId: Integer;
    FNumero: string;
    FDetalhe: string;
  public
    constructor Create(AOrdemId: Integer; const ANumero, ADetalhe: string); reintroduce;
    function Descricao: string; override;
    property OrdemId: Integer read FOrdemId;
    property Numero: string read FNumero;
    property Detalhe: string read FDetalhe;
  end;

implementation

{ TPedidoConfirmado }

constructor TPedidoConfirmado.Create(APedidoId: Integer; const ANumero: string;
  AClienteId: Integer; ATotal: Currency);
begin
  inherited Create;
  FPedidoId := APedidoId;
  FNumero := ANumero;
  FClienteId := AClienteId;
  FTotal := ATotal;
end;

function TPedidoConfirmado.Descricao: string;
begin
  Result := Format('Pedido %s confirmado no valor de %s',
    [FNumero, TFmt.Moeda(FTotal)]);
end;

{ TPedidoCancelado }

constructor TPedidoCancelado.Create(APedidoId: Integer;
  const ANumero, AMotivo: string; AStatusAnterior: TStatusPedido);
begin
  inherited Create;
  FPedidoId := APedidoId;
  FNumero := ANumero;
  FMotivo := AMotivo;
  FStatusAnterior := AStatusAnterior;
end;

function TPedidoCancelado.Descricao: string;
begin
  Result := Format('Pedido %s cancelado (estava %s). Motivo: %s',
    [FNumero, StatusPedidoDescr(FStatusAnterior), FMotivo]);
end;

{ TEstoqueBaixo }

constructor TEstoqueBaixo.Create(AProdutoId: Integer;
  const ACodigo, ADescricao: string; ASaldo, AMinimo: Integer);
begin
  inherited Create;
  FProdutoId := AProdutoId;
  FCodigo := ACodigo;
  FDescricao := ADescricao;
  FSaldo := ASaldo;
  FMinimo := AMinimo;
end;

function TEstoqueBaixo.Descricao: string;
begin
  Result := Format('Estoque baixo: %s (%s) saldo %d, minimo %d',
    [FCodigo, FDescricao, FSaldo, FMinimo]);
end;

{ TPagamentoAprovado }

constructor TPagamentoAprovado.Create(APedidoId: Integer; AValor: Currency;
  AForma: TFormaPagamento);
begin
  inherited Create;
  FPedidoId := APedidoId;
  FValor := AValor;
  FForma := AForma;
end;

function TPagamentoAprovado.Descricao: string;
begin
  Result := Format('Pagamento de %s aprovado para o pedido %d via %s',
    [TFmt.Moeda(FValor), FPedidoId, FormaPagamentoDescr(FForma)]);
end;

{ TLimiteCreditoExcedido }

constructor TLimiteCreditoExcedido.Create(AClienteId: Integer;
  const ANomeCliente: string; ALimite, ASolicitado: Currency);
begin
  inherited Create;
  FClienteId := AClienteId;
  FNomeCliente := ANomeCliente;
  FLimite := ALimite;
  FSolicitado := ASolicitado;
end;

function TLimiteCreditoExcedido.Descricao: string;
begin
  Result := Format('Cliente %s excedeu o limite: limite %s, solicitado %s',
    [FNomeCliente, TFmt.Moeda(FLimite), TFmt.Moeda(FSolicitado)]);
end;

{ TOrdemLiberada }

constructor TOrdemLiberada.Create(AOrdemId: Integer;
  const ANumero, ACodigoProduto: string; AQuantidade: Double;
  ACustoMaterial: Currency);
begin
  inherited Create;
  FOrdemId := AOrdemId;
  FNumero := ANumero;
  FCodigoProduto := ACodigoProduto;
  FQuantidade := AQuantidade;
  FCustoMaterial := ACustoMaterial;
end;

function TOrdemLiberada.Descricao: string;
begin
  Result := Format('OP %s liberada: %.2f x %s, material requisitado %s',
    [FNumero, FQuantidade, FCodigoProduto, TFmt.Moeda(FCustoMaterial)]);
end;

{ TApontamentoRegistrado }

constructor TApontamentoRegistrado.Create(AOrdemId: Integer;
  const ANumero: string; ASequencia: Integer;
  AQuantidadeBoa, AQuantidadeRefugo: Double; const AOperador: string);
begin
  inherited Create;
  FOrdemId := AOrdemId;
  FNumero := ANumero;
  FSequencia := ASequencia;
  FQuantidadeBoa := AQuantidadeBoa;
  FQuantidadeRefugo := AQuantidadeRefugo;
  FOperador := AOperador;
end;

function TApontamentoRegistrado.Descricao: string;
begin
  Result := Format('OP %s op %d: %.2f boas, %.2f refugo (%s)',
    [FNumero, FSequencia, FQuantidadeBoa, FQuantidadeRefugo, FOperador]);
end;

{ TOrdemConcluida }

constructor TOrdemConcluida.Create(AOrdemId: Integer; const ANumero: string;
  AQuantidadeProduzida, AQuantidadeRefugada: Double; AVariacaoCusto: Currency);
begin
  inherited Create;
  FOrdemId := AOrdemId;
  FNumero := ANumero;
  FQuantidadeProduzida := AQuantidadeProduzida;
  FQuantidadeRefugada := AQuantidadeRefugada;
  FVariacaoCusto := AVariacaoCusto;
end;

function TOrdemConcluida.Descricao: string;
begin
  Result := Format('OP %s concluida: %.2f produzidas, %.2f refugadas, ' +
    'variacao de custo %s', [FNumero, FQuantidadeProduzida,
    FQuantidadeRefugada, TFmt.Moeda(FVariacaoCusto)]);
end;

{ TFaltaDeMaterial }

constructor TFaltaDeMaterial.Create(AOrdemId: Integer;
  const ANumero, ADetalhe: string);
begin
  inherited Create;
  FOrdemId := AOrdemId;
  FNumero := ANumero;
  FDetalhe := ADetalhe;
end;

function TFaltaDeMaterial.Descricao: string;
begin
  Result := Format('OP %s travada por falta de material: %s',
    [FNumero, FDetalhe]);
end;

end.
