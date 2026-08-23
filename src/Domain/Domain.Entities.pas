{*******************************************************************************
  Domain.Entities

  O MODELO RICO do dominio: as entidades carregam dados E comportamento.
  (O oposto seria o "modelo anemico", onde a classe so tem get/set e as regras
   vivem espalhadas em servicos ou, pior, nos botoes da tela.)

  ESTUDO - conceitos demonstrados aqui:
    * Heranca + metodos virtuais/abstratos/override
    * Template Method: Clone/ToJson/FromJson tem versao generica na base e
      versao especializada em TPedido (que possui uma colecao filha)
    * Aggregate Root: TPedido controla o ciclo de vida dos seus TItemPedido;
      ninguem mexe nos itens por fora
    * Atributos de validacao declarativos (ver Core.Validation)
    * Encapsulamento: propriedades somente-leitura para valores calculados
    * TObjectList<T> com OwnsObjects e destruicao correta
*******************************************************************************}
unit Domain.Entities;

interface

uses
  System.SysUtils,
  System.Math,
  System.JSON,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  System.Generics.Defaults,
  Core.Types,
  Core.Json,
  Core.Validation,
  Domain.Enums;

type
  TEntidade = class;
  TEntidadeClass = class of TEntidade;

  { --------------------------------------------------------------------------
    Raiz de toda entidade persistivel.
    -------------------------------------------------------------------------- }
  TEntidade = class abstract
  private
    FId: Integer;
    FCriadoEm: TDateTime;
    FAtualizadoEm: TDateTime;
  protected
    /// Ganchos para as filhas acrescentarem regras que atributos nao expressam.
    procedure ValidarRegras(AErros: TList<string>); virtual;
  public
    constructor Create; virtual;

    /// Copia as propriedades escalares para outro objeto (via RTTI).
    procedure CopiarPara(ADestino: TEntidade); virtual;
    /// Cria uma copia independente. Usado pelo Unit of Work para rollback.
    function Clone: TEntidade; virtual;

    function ToJson: TJSONObject; virtual;
    procedure FromJson(AJson: TJSONObject); virtual;

    /// Junta as regras declarativas (atributos) com as regras programadas.
    function Erros: TArray<string>;
    procedure Validar;

    procedure MarcarAtualizado;
    function Resumo: string; virtual; abstract;

    property Id: Integer read FId write FId;
    property CriadoEm: TDateTime read FCriadoEm write FCriadoEm;
    property AtualizadoEm: TDateTime read FAtualizadoEm write FAtualizadoEm;
  end;

  { --------------------------------------------------------------------------
    CLIENTE
    -------------------------------------------------------------------------- }
  TCliente = class(TEntidade)
  private
    FNome: string;
    FDocumento: string;
    FEmail: string;
    FTelefone: string;
    FCidade: string;
    FUF: string;
    FCategoria: TCategoriaCliente;
    FLimiteCredito: Currency;
    FAtivo: Boolean;
  public
    constructor Create; override;

    function DescontoCategoria: Double;
    function EhPessoaJuridica: Boolean;
    function DocumentoFormatado: string;
    function Resumo: string; override;

    [Rotulo('Nome')] [Obrigatorio] [TamanhoMin(3)] [TamanhoMax(80)]
    property Nome: string read FNome write FNome;

    [Rotulo('Documento')] [Obrigatorio] [CpfOuCnpj]
    property Documento: string read FDocumento write FDocumento;

    [Rotulo('E-mail')] [EmailValido] [TamanhoMax(120)]
    property Email: string read FEmail write FEmail;

    [Rotulo('Telefone')] [TamanhoMax(20)]
    property Telefone: string read FTelefone write FTelefone;

    [Rotulo('Cidade')] [TamanhoMax(60)]
    property Cidade: string read FCidade write FCidade;

    [Rotulo('UF')] [TamanhoMax(2)]
    property UF: string read FUF write FUF;

    property Categoria: TCategoriaCliente read FCategoria write FCategoria;

    [Rotulo('Limite de credito')] [NaoNegativo]
    property LimiteCredito: Currency read FLimiteCredito write FLimiteCredito;

    property Ativo: Boolean read FAtivo write FAtivo;
  end;

  { --------------------------------------------------------------------------
    PRODUTO
    -------------------------------------------------------------------------- }
  TProduto = class(TEntidade)
  private
    FCodigo: string;
    FDescricao: string;
    FCategoria: string;
    FPreco: Currency;
    FEstoque: Integer;
    FEstoqueMinimo: Integer;
    FAtivo: Boolean;
    FTipo: TTipoProduto;
    FUnidade: string;
    FCustoMedio: Currency;
    FLeadTimeDias: Integer;
    FLoteMinimo: Integer;
  public
    constructor Create; override;

    function EmFalta: Boolean;
    function AbaixoDoMinimo: Boolean;
    function TemEstoquePara(AQuantidade: Integer): Boolean;
    function ValorEmEstoque: Currency;
    function Resumo: string; override;

    /// Item fabricado internamente (tem estrutura e roteiro)?
    function EhFabricado: Boolean;
    /// Item comprado de terceiros?
    function EhComprado: Boolean;
    { CUSTO MEDIO MOVEL - o metodo classico de custeio de estoque.
      A cada entrada, o custo novo e a media ponderada entre o que ja havia
      e o que entrou. Saidas NAO alteram o custo medio, so o saldo. }
    procedure AtualizarCustoMedio(AQuantidadeEntrada: Integer;
      ACustoUnitarioEntrada: Currency);

    /// Unico ponto que altera estoque: mantem a regra "nunca negativo".
    procedure MovimentarEstoque(ATipo: TTipoMovimento; AQuantidade: Integer);

    [Rotulo('Codigo')] [Obrigatorio] [TamanhoMin(2)] [TamanhoMax(20)]
    property Codigo: string read FCodigo write FCodigo;

    [Rotulo('Descricao')] [Obrigatorio] [TamanhoMin(3)] [TamanhoMax(100)]
    property Descricao: string read FDescricao write FDescricao;

    [Rotulo('Categoria')] [TamanhoMax(40)]
    property Categoria: string read FCategoria write FCategoria;

    [Rotulo('Preco')] [Faixa(0.01, 9999999.0)]
    property Preco: Currency read FPreco write FPreco;

    [Rotulo('Estoque')] [NaoNegativo]
    property Estoque: Integer read FEstoque write FEstoque;

    [Rotulo('Estoque minimo')] [NaoNegativo]
    property EstoqueMinimo: Integer read FEstoqueMinimo write FEstoqueMinimo;

    property Ativo: Boolean read FAtivo write FAtivo;

    // ---------------- campos industriais ----------------
    property Tipo: TTipoProduto read FTipo write FTipo;

    [Rotulo('Unidade')] [Obrigatorio] [TamanhoMax(6)]
    property Unidade: string read FUnidade write FUnidade;

    /// Custo medio movel: base para valorizar estoque e custear a producao.
    [Rotulo('Custo medio')] [NaoNegativo]
    property CustoMedio: Currency read FCustoMedio write FCustoMedio;

    /// Dias entre pedir/produzir e ter o item disponivel (usado no MRP).
    [Rotulo('Lead time')] [NaoNegativo]
    property LeadTimeDias: Integer read FLeadTimeDias write FLeadTimeDias;

    [Rotulo('Lote minimo')] [NaoNegativo]
    property LoteMinimo: Integer read FLoteMinimo write FLoteMinimo;
  end;

  { --------------------------------------------------------------------------
    ITEM DE PEDIDO - parte interna do agregado TPedido
    -------------------------------------------------------------------------- }
  TItemPedido = class(TEntidade)
  private
    FPedidoId: Integer;
    FProdutoId: Integer;
    FCodigoProduto: string;
    FDescricaoProduto: string;
    FQuantidade: Integer;
    FPrecoUnitario: Currency;
    FDescontoPercentual: Double;
    function GetSubtotal: Currency;
    function GetValorDesconto: Currency;
    function GetTotal: Currency;
  public
    constructor Create; override;
    function Resumo: string; override;

    /// Chave do pai. O agregado cuida disso; o banco precisa dela na tabela filha.
    property PedidoId: Integer read FPedidoId write FPedidoId;

    [Rotulo('Produto')] [Obrigatorio]
    property ProdutoId: Integer read FProdutoId write FProdutoId;

    property CodigoProduto: string read FCodigoProduto write FCodigoProduto;

    [Rotulo('Descricao do produto')] [Obrigatorio]
    property DescricaoProduto: string read FDescricaoProduto write FDescricaoProduto;

    [Rotulo('Quantidade')] [Faixa(1.0, 100000.0)]
    property Quantidade: Integer read FQuantidade write FQuantidade;

    [Rotulo('Preco unitario')] [Faixa(0.01, 9999999.0)]
    property PrecoUnitario: Currency read FPrecoUnitario write FPrecoUnitario;

    [Rotulo('Desconto do item')] [Faixa(0.0, 1.0)]
    property DescontoPercentual: Double read FDescontoPercentual write FDescontoPercentual;

    // Somente leitura => nao vao para o JSON (nao sao "writable").
    property Subtotal: Currency read GetSubtotal;
    property ValorDesconto: Currency read GetValorDesconto;
    property Total: Currency read GetTotal;
  end;

  { --------------------------------------------------------------------------
    PEDIDO - AGGREGATE ROOT

    Regras que vivem aqui dentro:
      * so aceita alteracao de itens enquanto estiver em Rascunho
      * transicoes de status seguem a maquina de estados de Domain.Enums
      * os totais sao sempre calculados, nunca "chutados" de fora
    -------------------------------------------------------------------------- }
  TPedido = class(TEntidade)
  private
    FNumero: string;
    FClienteId: Integer;
    FNomeCliente: string;
    FStatus: TStatusPedido;
    FFormaPagamento: TFormaPagamento;
    FObservacao: string;
    FFrete: Currency;
    FDescontoNegociado: Currency;
    FDataConfirmacao: TDateTime;
    FDataFechamento: TDateTime;
    FItens: TObjectList<TItemPedido>;
    function GetTotalBruto: Currency;
    function GetTotalDescontoItens: Currency;
    function GetTotalLiquido: Currency;
    function GetQuantidadeItens: Integer;
    procedure ExigirRascunho(const AOperacao: string);
  protected
    procedure ValidarRegras(AErros: TList<string>); override;
  public
    constructor Create; override;
    destructor Destroy; override;

    // --- manipulacao de itens (so em rascunho) ---
    function AdicionarItem(AProduto: TProduto; AQuantidade: Integer;
      ADescontoPercentual: Double = 0): TItemPedido;
    procedure RemoverItem(AIndice: Integer);
    procedure LimparItens;
    function ItemDoProduto(AProdutoId: Integer): TItemPedido;

    // --- maquina de estados ---
    procedure MudarStatus(ANovo: TStatusPedido);
    function PodeMudarPara(ANovo: TStatusPedido): Boolean;
    function EstaEmAberto: Boolean;
    function ReservaEstoque: Boolean;

    // --- ciclo de vida / serializacao ---
    function Clone: TEntidade; override;
    function ToJson: TJSONObject; override;
    procedure FromJson(AJson: TJSONObject); override;
    function Resumo: string; override;

    /// A lista e exposta como leitura; alteracoes passam pelos metodos acima.
    property Itens: TObjectList<TItemPedido> read FItens;

    [Rotulo('Numero')] [Obrigatorio]
    property Numero: string read FNumero write FNumero;

    [Rotulo('Cliente')] [Obrigatorio]
    property ClienteId: Integer read FClienteId write FClienteId;

    property NomeCliente: string read FNomeCliente write FNomeCliente;
    property Status: TStatusPedido read FStatus write FStatus;
    property FormaPagamento: TFormaPagamento read FFormaPagamento write FFormaPagamento;

    [Rotulo('Observacao')] [TamanhoMax(200)]
    property Observacao: string read FObservacao write FObservacao;

    [Rotulo('Frete')] [NaoNegativo]
    property Frete: Currency read FFrete write FFrete;

    [Rotulo('Desconto negociado')] [NaoNegativo]
    property DescontoNegociado: Currency read FDescontoNegociado write FDescontoNegociado;

    property DataConfirmacao: TDateTime read FDataConfirmacao write FDataConfirmacao;
    property DataFechamento: TDateTime read FDataFechamento write FDataFechamento;

    property TotalBruto: Currency read GetTotalBruto;
    property TotalDescontoItens: Currency read GetTotalDescontoItens;
    property TotalLiquido: Currency read GetTotalLiquido;
    property QuantidadeItens: Integer read GetQuantidadeItens;
  end;

  { --------------------------------------------------------------------------
    MOVIMENTO DE ESTOQUE - registro historico (append only)
    -------------------------------------------------------------------------- }
  TMovimentoEstoque = class(TEntidade)
  private
    FProdutoId: Integer;
    FCodigoProduto: string;
    FTipo: TTipoMovimento;
    FQuantidade: Integer;
    FSaldoResultante: Integer;
    FMotivo: string;
    FPedidoId: Integer;
    FOrdemProducaoId: Integer;
    FCustoUnitario: Currency;
  public
    constructor Create; override;
    function Resumo: string; override;
    function EhEntrada: Boolean;

    [Rotulo('Produto')] [Obrigatorio]
    property ProdutoId: Integer read FProdutoId write FProdutoId;
    property CodigoProduto: string read FCodigoProduto write FCodigoProduto;
    property Tipo: TTipoMovimento read FTipo write FTipo;

    [Rotulo('Quantidade')] [Faixa(1.0, 1000000.0)]
    property Quantidade: Integer read FQuantidade write FQuantidade;

    property SaldoResultante: Integer read FSaldoResultante write FSaldoResultante;

    [Rotulo('Motivo')] [Obrigatorio] [TamanhoMax(80)]
    property Motivo: string read FMotivo write FMotivo;

    property PedidoId: Integer read FPedidoId write FPedidoId;
    /// Preenchido quando o movimento nasceu de uma ordem de producao.
    property OrdemProducaoId: Integer read FOrdemProducaoId write FOrdemProducaoId;
    /// Custo unitario praticado no movimento (base do custo medio movel).
    property CustoUnitario: Currency read FCustoUnitario write FCustoUnitario;
  end;

  { --------------------------------------------------------------------------
    PAGAMENTO
    -------------------------------------------------------------------------- }
  TPagamento = class(TEntidade)
  private
    FPedidoId: Integer;
    FValor: Currency;
    FForma: TFormaPagamento;
    FAutorizado: Boolean;
    FAutorizacao: string;
  public
    constructor Create; override;
    function Resumo: string; override;

    [Rotulo('Pedido')] [Obrigatorio]
    property PedidoId: Integer read FPedidoId write FPedidoId;

    [Rotulo('Valor')] [Faixa(0.01, 99999999.0)]
    property Valor: Currency read FValor write FValor;

    property Forma: TFormaPagamento read FForma write FForma;
    property Autorizado: Boolean read FAutorizado write FAutorizado;
    property Autorizacao: string read FAutorizacao write FAutorizacao;
  end;

implementation

{ TEntidade }

constructor TEntidade.Create;
begin
  inherited Create;
  FCriadoEm := Now;
  FAtualizadoEm := FCriadoEm;
end;

procedure TEntidade.ValidarRegras(AErros: TList<string>);
begin
  // por padrao nao ha regras extras; filhas sobrescrevem
end;

function TEntidade.Erros: TArray<string>;
var
  LLista: TList<string>;
begin
  LLista := TList<string>.Create;
  try
    LLista.AddRange(TValidador.Validar(Self)); // regras declarativas
    ValidarRegras(LLista);                     // regras programadas
    Result := LLista.ToArray;
  finally
    LLista.Free;
  end;
end;

procedure TEntidade.Validar;
var
  LErros: TArray<string>;
begin
  LErros := Erros;
  if Length(LErros) > 0 then
    raise EValidacao.Create(LErros);
end;

procedure TEntidade.MarcarAtualizado;
begin
  FAtualizadoEm := Now;
end;

procedure TEntidade.CopiarPara(ADestino: TEntidade);
var
  LCtx: TRttiContext;
  LProp: TRttiProperty;
begin
  if ADestino = nil then
    Exit;
  LCtx := TRttiContext.Create;
  try
    for LProp in LCtx.GetType(ClassType).GetProperties do
    begin
      if (not LProp.IsReadable) or (not LProp.IsWritable) then
        Continue;
      if LProp.Visibility < mvPublic then
        Continue;
      // colecoes e objetos ficam por conta de quem sobrescreve (ver TPedido)
      if LProp.PropertyType.TypeKind in [tkClass, tkInterface, tkMethod] then
        Continue;
      LProp.SetValue(ADestino, LProp.GetValue(Self));
    end;
  finally
    LCtx.Free;
  end;
end;

function TEntidade.Clone: TEntidade;
var
  LCtx: TRttiContext;
  LTipo: TRttiInstanceType;
begin
  LCtx := TRttiContext.Create;
  try
    // Instancia a MESMA classe do objeto atual, seja ela qual for.
    LTipo := LCtx.GetType(ClassType) as TRttiInstanceType;
    Result := TEntidadeClass(LTipo.MetaclassType).Create;
  finally
    LCtx.Free;
  end;
  CopiarPara(Result);
end;

function TEntidade.ToJson: TJSONObject;
begin
  Result := TJsonRtti.ObjetoParaJson(Self);
end;

procedure TEntidade.FromJson(AJson: TJSONObject);
begin
  TJsonRtti.JsonParaObjeto(AJson, Self);
end;

{ TCliente }

constructor TCliente.Create;
begin
  inherited Create;
  FCategoria := ccComum;
  FAtivo := True;
  FLimiteCredito := 1000;
  FUF := 'SP';
end;

function TCliente.DescontoCategoria: Double;
begin
  Result := DescontoDaCategoria(FCategoria);
end;

function TCliente.EhPessoaJuridica: Boolean;
begin
  Result := Length(SomenteDigitos(FDocumento)) = 14;
end;

function TCliente.DocumentoFormatado: string;
var
  LDig: string;
begin
  LDig := SomenteDigitos(FDocumento);
  if Length(LDig) = 11 then
    Result := Format('%s.%s.%s-%s', [Copy(LDig, 1, 3), Copy(LDig, 4, 3),
      Copy(LDig, 7, 3), Copy(LDig, 10, 2)])
  else if Length(LDig) = 14 then
    Result := Format('%s.%s.%s/%s-%s', [Copy(LDig, 1, 2), Copy(LDig, 3, 3),
      Copy(LDig, 6, 3), Copy(LDig, 9, 4), Copy(LDig, 13, 2)])
  else
    Result := FDocumento;
end;

function TCliente.Resumo: string;
begin
  Result := Format('#%d %s (%s) - limite %s', [Id, FNome,
    CategoriaClienteDescr(FCategoria), TFmt.Moeda(FLimiteCredito)]);
end;

{ TProduto }

constructor TProduto.Create;
begin
  inherited Create;
  FAtivo := True;
  FEstoqueMinimo := 5;
  FTipo := tpRevenda;
  FUnidade := 'UN';
  FLoteMinimo := 1;
end;

function TProduto.EhFabricado: Boolean;
begin
  Result := FTipo in TIPOS_FABRICADOS;
end;

function TProduto.EhComprado: Boolean;
begin
  Result := FTipo in TIPOS_COMPRADOS;
end;

procedure TProduto.AtualizarCustoMedio(AQuantidadeEntrada: Integer;
  ACustoUnitarioEntrada: Currency);
var
  LValorAtual, LValorEntrada: Currency;
  LSaldoFinal: Integer;
begin
  if AQuantidadeEntrada <= 0 then
    Exit;

  // Saldo ANTES da entrada (o chamador movimenta o estoque separadamente).
  LValorAtual := FEstoque * FCustoMedio;
  LValorEntrada := AQuantidadeEntrada * ACustoUnitarioEntrada;
  LSaldoFinal := FEstoque + AQuantidadeEntrada;

  if LSaldoFinal <= 0 then
    Exit;

  FCustoMedio := RoundTo((LValorAtual + LValorEntrada) / LSaldoFinal, -4);
  MarcarAtualizado;
end;

function TProduto.EmFalta: Boolean;
begin
  Result := FEstoque <= 0;
end;

function TProduto.AbaixoDoMinimo: Boolean;
begin
  Result := FEstoque < FEstoqueMinimo;
end;

function TProduto.TemEstoquePara(AQuantidade: Integer): Boolean;
begin
  Result := FEstoque >= AQuantidade;
end;

function TProduto.ValorEmEstoque: Currency;
begin
  Result := FEstoque * FPreco;
end;

procedure TProduto.MovimentarEstoque(ATipo: TTipoMovimento; AQuantidade: Integer);
begin
  if AQuantidade <= 0 then
    raise EDominio.Create('A quantidade movimentada deve ser positiva.');

  case ATipo of
    tmEntrada, tmProducao:
      Inc(FEstoque, AQuantidade);
    tmSaida, tmConsumo:
      begin
        if FEstoque < AQuantidade then
          raise EDominio.CreateFmt(
            'Estoque insuficiente para "%s": disponivel %d, solicitado %d.',
            [FDescricao, FEstoque, AQuantidade]);
        Dec(FEstoque, AQuantidade);
      end;
    tmAjuste:
      FEstoque := AQuantidade;
  end;
  MarcarAtualizado;
end;

function TProduto.Resumo: string;
begin
  Result := Format('#%d [%s] %s - %s (estoque %d)',
    [Id, FCodigo, FDescricao, TFmt.Moeda(FPreco), FEstoque]);
end;

{ TItemPedido }

constructor TItemPedido.Create;
begin
  inherited Create;
  FQuantidade := 1;
end;

function TItemPedido.GetSubtotal: Currency;
begin
  Result := FQuantidade * FPrecoUnitario;
end;

function TItemPedido.GetValorDesconto: Currency;
begin
  Result := RoundTo(GetSubtotal * FDescontoPercentual, -2);
end;

function TItemPedido.GetTotal: Currency;
begin
  Result := GetSubtotal - GetValorDesconto;
end;

function TItemPedido.Resumo: string;
begin
  Result := Format('%-30s %4d x %10s = %12s',
    [Copy(FDescricaoProduto, 1, 30), FQuantidade,
     TFmt.Moeda(FPrecoUnitario), TFmt.Moeda(GetTotal)]);
end;

{ TPedido }

constructor TPedido.Create;
begin
  inherited Create;
  FItens := TObjectList<TItemPedido>.Create(True); // True = a lista destroi
  FStatus := spRascunho;
  FFormaPagamento := fpPix;
end;

destructor TPedido.Destroy;
begin
  FItens.Free; // destroi todos os itens junto (agregado)
  inherited;
end;

procedure TPedido.ExigirRascunho(const AOperacao: string);
begin
  if FStatus <> spRascunho then
    raise EDominio.CreateFmt(
      'Nao e possivel %s: o pedido %s esta com status "%s".',
      [AOperacao, FNumero, StatusPedidoDescr(FStatus)]);
end;

function TPedido.AdicionarItem(AProduto: TProduto; AQuantidade: Integer;
  ADescontoPercentual: Double): TItemPedido;
var
  LExistente: TItemPedido;
begin
  ExigirRascunho('adicionar itens');

  if AProduto = nil then
    raise EDominio.Create('Produto nao informado.');
  if not AProduto.Ativo then
    raise EDominio.CreateFmt('O produto "%s" esta inativo.', [AProduto.Descricao]);
  if AQuantidade <= 0 then
    raise EDominio.Create('A quantidade deve ser maior que zero.');
  if (ADescontoPercentual < 0) or (ADescontoPercentual > 1) then
    raise EDominio.Create('O desconto do item deve estar entre 0 e 1 (0% a 100%).');

  // Mesmo produto duas vezes = soma quantidade, nao duplica linha.
  LExistente := ItemDoProduto(AProduto.Id);
  if LExistente <> nil then
  begin
    LExistente.Quantidade := LExistente.Quantidade + AQuantidade;
    LExistente.MarcarAtualizado;
    MarcarAtualizado;
    Exit(LExistente);
  end;

  Result := TItemPedido.Create;
  Result.ProdutoId := AProduto.Id;
  Result.CodigoProduto := AProduto.Codigo;
  Result.DescricaoProduto := AProduto.Descricao;
  Result.Quantidade := AQuantidade;
  Result.PrecoUnitario := AProduto.Preco;  // congela o preco do momento da venda
  Result.DescontoPercentual := ADescontoPercentual;
  FItens.Add(Result);
  MarcarAtualizado;
end;

procedure TPedido.RemoverItem(AIndice: Integer);
begin
  ExigirRascunho('remover itens');
  if (AIndice < 0) or (AIndice >= FItens.Count) then
    raise EDominio.CreateFmt('Item %d inexistente no pedido.', [AIndice + 1]);
  FItens.Delete(AIndice);
  MarcarAtualizado;
end;

procedure TPedido.LimparItens;
begin
  ExigirRascunho('limpar itens');
  FItens.Clear;
  MarcarAtualizado;
end;

function TPedido.ItemDoProduto(AProdutoId: Integer): TItemPedido;
var
  LItem: TItemPedido;
begin
  for LItem in FItens do
    if LItem.ProdutoId = AProdutoId then
      Exit(LItem);
  Result := nil;
end;

function TPedido.PodeMudarPara(ANovo: TStatusPedido): Boolean;
begin
  Result := TransicaoPermitida(FStatus, ANovo);
end;

procedure TPedido.MudarStatus(ANovo: TStatusPedido);
begin
  if not PodeMudarPara(ANovo) then
    raise EDominio.CreateFmt('Transicao invalida: %s -> %s (pedido %s).',
      [StatusPedidoDescr(FStatus), StatusPedidoDescr(ANovo), FNumero]);

  FStatus := ANovo;
  case ANovo of
    spConfirmado: FDataConfirmacao := Now;
    spEntregue, spCancelado: FDataFechamento := Now;
  end;
  MarcarAtualizado;
end;

function TPedido.EstaEmAberto: Boolean;
begin
  Result := FStatus in STATUS_EM_ABERTO;
end;

function TPedido.ReservaEstoque: Boolean;
begin
  Result := FStatus in STATUS_COM_RESERVA;
end;

function TPedido.GetTotalBruto: Currency;
var
  LItem: TItemPedido;
begin
  Result := 0;
  for LItem in FItens do
    Result := Result + LItem.Subtotal;
end;

function TPedido.GetTotalDescontoItens: Currency;
var
  LItem: TItemPedido;
begin
  Result := 0;
  for LItem in FItens do
    Result := Result + LItem.ValorDesconto;
end;

function TPedido.GetTotalLiquido: Currency;
begin
  Result := GetTotalBruto - GetTotalDescontoItens - FDescontoNegociado + FFrete;
  if Result < 0 then
    Result := 0;
end;

function TPedido.GetQuantidadeItens: Integer;
var
  LItem: TItemPedido;
begin
  Result := 0;
  for LItem in FItens do
    Inc(Result, LItem.Quantidade);
end;

procedure TPedido.ValidarRegras(AErros: TList<string>);
begin
  inherited;
  if FItens.Count = 0 then
    AErros.Add('Pedido: deve ter pelo menos um item.');
  if FDescontoNegociado > GetTotalBruto then
    AErros.Add('Pedido: o desconto negociado nao pode superar o total bruto.');
end;

function TPedido.Clone: TEntidade;
var
  LCopia: TPedido;
  LItem: TItemPedido;
begin
  Result := inherited Clone;      // copia escalares e cria a instancia certa
  LCopia := TPedido(Result);
  LCopia.FItens.Clear;
  for LItem in FItens do
    LCopia.FItens.Add(TItemPedido(LItem.Clone)); // copia PROFUNDA dos itens
end;

function TPedido.ToJson: TJSONObject;
var
  LArray: TJSONArray;
  LItem: TItemPedido;
begin
  Result := inherited ToJson;  // escalares via RTTI
  LArray := TJSONArray.Create;
  for LItem in FItens do
    LArray.AddElement(LItem.ToJson);
  Result.AddPair('Itens', LArray);
end;

procedure TPedido.FromJson(AJson: TJSONObject);
var
  LValor: TJSONValue;
  LArray: TJSONArray;
  LElemento: TJSONValue;
  LItem: TItemPedido;
begin
  inherited FromJson(AJson);
  FItens.Clear;

  LValor := AJson.GetValue('Itens');
  if not (LValor is TJSONArray) then
    Exit;

  LArray := TJSONArray(LValor);
  for LElemento in LArray do
    if LElemento is TJSONObject then
    begin
      LItem := TItemPedido.Create;
      try
        LItem.FromJson(TJSONObject(LElemento));
        FItens.Add(LItem);
      except
        LItem.Free;
        raise;
      end;
    end;
end;

function TPedido.Resumo: string;
begin
  Result := Format('#%d %s - %s - %d item(ns) - %s - %s',
    [Id, FNumero, FNomeCliente, FItens.Count, TFmt.Moeda(GetTotalLiquido),
     StatusPedidoDescr(FStatus)]);
end;

{ TMovimentoEstoque }

constructor TMovimentoEstoque.Create;
begin
  inherited Create;
  FTipo := tmEntrada;
  FQuantidade := 1;
end;

function TMovimentoEstoque.EhEntrada: Boolean;
begin
  Result := MovimentoEhEntrada(FTipo);
end;

function TMovimentoEstoque.Resumo: string;
var
  LSinal: string;
begin
  if EhEntrada then
    LSinal := '+'
  else if FTipo = tmAjuste then
    LSinal := '='
  else
    LSinal := '-';
  Result := Format('%s %-9s %-12s %s%-5d -> saldo %5d  (%s)',
    [TFmt.DataHora(CriadoEm), TipoMovimentoDescr(FTipo), FCodigoProduto,
     LSinal, FQuantidade, FSaldoResultante, FMotivo]);
end;

{ TPagamento }

constructor TPagamento.Create;
begin
  inherited Create;
  FForma := fpPix;
end;

function TPagamento.Resumo: string;
var
  LSituacao: string;
begin
  if FAutorizado then
    LSituacao := 'AUTORIZADO'
  else
    LSituacao := 'RECUSADO';
  Result := Format('#%d pedido %d - %s via %s [%s] %s',
    [Id, FPedidoId, TFmt.Moeda(FValor), FormaPagamentoDescr(FForma),
     LSituacao, FAutorizacao]);
end;

end.
