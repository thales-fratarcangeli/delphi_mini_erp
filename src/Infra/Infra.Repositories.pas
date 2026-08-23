{*******************************************************************************
  Infra.Repositories

  Implementacao dos repositorios EM MEMORIA.

  ESTUDO - conceitos demonstrados aqui:
    * Classe GENERICA implementando interface generica: escreve-se o CRUD uma
      unica vez e ele serve para todas as entidades
    * Heranca de classe generica instanciada:
        TRepositorioClientes = class(TRepositorioMemoria<TCliente>, IRepositorioClientes)
      -> reaproveita todo o CRUD e acrescenta as consultas especificas
    * TObjectDictionary com doOwnsValues: o dicionario destroi as entidades
    * TCriticalSection: acesso seguro entre threads
    * TArray.Sort + TComparer<T>.Construct com metodo anonimo
    * Restricao de generico: <T: TEntidade>

  Trocar isto por um repositorio com FireDAC/SQL nao exige mexer em NENHUMA
  linha do dominio - so no App.Bootstrap, onde o registro e feito.
*******************************************************************************}
unit Infra.Repositories;

interface

uses
  System.SysUtils,
  System.TypInfo,
  System.SyncObjs,
  System.Generics.Collections,
  System.Generics.Defaults,
  Core.Types,
  Domain.Entities,
  Domain.Enums,
  Domain.Interfaces,
  Domain.Producao,
  Domain.Specifications;

type
  TRepositorioMemoria<T: TEntidade> = class(TInterfacedObject, IRepositorio<T>)
  private
    FItens: TObjectDictionary<Integer, T>;
    FProximoId: Integer;
    FLock: TCriticalSection;
    FNome: string;
  protected
    /// Executa ABloco com o repositorio travado (evita repetir try/finally).
    procedure Travado(const ABloco: TProc);
    function TodosSemTrava: TArray<T>;
  public
    constructor Create;
    destructor Destroy; override;

    function Adicionar(AEntidade: T): T;
    procedure Atualizar(AEntidade: T);
    procedure Remover(AId: Integer);
    function PorId(AId: Integer): T;
    function TentarPorId(AId: Integer; out AEntidade: T): Boolean;
    function Existe(AId: Integer): Boolean;
    function Todos: TArray<T>;
    function Buscar(const AEspec: ISpecification<T>): TArray<T>;
    function Primeiro(const AEspec: ISpecification<T>): T;
    function Contar: Integer;
    procedure Limpar;
    function NomeEntidade: string;
  end;

  TRepositorioClientes = class(TRepositorioMemoria<TCliente>, IRepositorioClientes)
  public
    function PorDocumento(const ADocumento: string): TCliente;
    function PorCategoria(ACategoria: TCategoriaCliente): TArray<TCliente>;
  end;

  TRepositorioProdutos = class(TRepositorioMemoria<TProduto>, IRepositorioProdutos)
  public
    function PorCodigo(const ACodigo: string): TProduto;
    function AbaixoDoMinimo: TArray<TProduto>;
    function Categorias: TArray<string>;
  end;

  TRepositorioPedidos = class(TRepositorioMemoria<TPedido>, IRepositorioPedidos)
  public
    function PorNumero(const ANumero: string): TPedido;
    function DoCliente(AClienteId: Integer): TArray<TPedido>;
    function ComStatus(const AStatus: TStatusPedidoSet): TArray<TPedido>;
    function ProximoNumero: string;
    function TotalEmAbertoDoCliente(AClienteId: Integer): Currency;
  end;

  TRepositorioMovimentos = class(TRepositorioMemoria<TMovimentoEstoque>,
    IRepositorioMovimentos)
  public
    function DoProduto(AProdutoId: Integer): TArray<TMovimentoEstoque>;
  end;

  TRepositorioPagamentos = class(TRepositorioMemoria<TPagamento>,
    IRepositorioPagamentos)
  public
    function DoPedido(APedidoId: Integer): TArray<TPagamento>;
  end;

  { ------------------------------ PCP ------------------------------ }

  TRepositorioCentros = class(TRepositorioMemoria<TCentroTrabalho>,
    IRepositorioCentros)
  public
    function PorCodigo(const ACodigo: string): TCentroTrabalho;
    function Ativos: TArray<TCentroTrabalho>;
  end;

  TRepositorioEstruturas = class(TRepositorioMemoria<TItemEstrutura>,
    IRepositorioEstruturas)
  public
    function DoProdutoPai(AProdutoPaiId: Integer): TArray<TItemEstrutura>;
    function OndeEUsado(AComponenteId: Integer): TArray<TItemEstrutura>;
    function Linha(AProdutoPaiId, AComponenteId: Integer): TItemEstrutura;
  end;

  TRepositorioRoteiros = class(TRepositorioMemoria<TOperacaoRoteiro>,
    IRepositorioRoteiros)
  public
    function DoProduto(AProdutoId: Integer): TArray<TOperacaoRoteiro>;
    function Operacao(AProdutoId, ASequencia: Integer): TOperacaoRoteiro;
  end;

  TRepositorioOrdens = class(TRepositorioMemoria<TOrdemProducao>,
    IRepositorioOrdens)
  public
    function PorNumero(const ANumero: string): TOrdemProducao;
    function ComStatus(const AStatus: TStatusOPSet): TArray<TOrdemProducao>;
    function DoProduto(AProdutoId: Integer): TArray<TOrdemProducao>;
    function ProximoNumero: string;
  end;

implementation

uses
  System.Math,
  Core.Validation;

{ TRepositorioMemoria<T> }

constructor TRepositorioMemoria<T>.Create;
begin
  inherited Create;
  // doOwnsValues: ao remover/limpar/destruir, as entidades sao liberadas.
  FItens := TObjectDictionary<Integer, T>.Create([doOwnsValues]);
  FLock := TCriticalSection.Create;
  FProximoId := 1;
  FNome := string(PTypeInfo(TypeInfo(T))^.Name);
end;

destructor TRepositorioMemoria<T>.Destroy;
begin
  FItens.Free;
  FLock.Free;
  inherited;
end;

procedure TRepositorioMemoria<T>.Travado(const ABloco: TProc);
begin
  FLock.Enter;
  try
    ABloco();
  finally
    FLock.Leave;
  end;
end;

function TRepositorioMemoria<T>.NomeEntidade: string;
begin
  Result := FNome;
end;

function TRepositorioMemoria<T>.Adicionar(AEntidade: T): T;
var
  LEntidade: T;
begin
  if AEntidade = nil then
    raise EDominio.Create('Tentativa de adicionar entidade nula.');

  LEntidade := AEntidade;
  Travado(
    procedure
    begin
      if LEntidade.Id = 0 then
      begin
        LEntidade.Id := FProximoId;
        Inc(FProximoId);
      end
      else
      begin
        if FItens.ContainsKey(LEntidade.Id) then
          raise EDominio.CreateFmt('Ja existe %s com Id %d.',
            [FNome, LEntidade.Id]);
        // mantem a sequencia coerente ao carregar dados de arquivo
        FProximoId := Max(FProximoId, LEntidade.Id + 1);
      end;
      FItens.Add(LEntidade.Id, LEntidade);
    end);
  Result := AEntidade;
end;

procedure TRepositorioMemoria<T>.Atualizar(AEntidade: T);
var
  LEntidade: T;
begin
  if AEntidade = nil then
    raise EDominio.Create('Tentativa de atualizar entidade nula.');

  LEntidade := AEntidade;
  Travado(
    procedure
    begin
      if not FItens.ContainsKey(LEntidade.Id) then
        raise ENaoEncontrado.Create(FNome, LEntidade.Id);
      // Como guardamos referencias vivas, o objeto ja esta atualizado.
      // O metodo existe para manter o contrato (e servir a um repo real).
      LEntidade.MarcarAtualizado;
    end);
end;

procedure TRepositorioMemoria<T>.Remover(AId: Integer);
begin
  Travado(
    procedure
    begin
      if not FItens.ContainsKey(AId) then
        raise ENaoEncontrado.Create(FNome, AId);
      FItens.Remove(AId); // doOwnsValues destroi a entidade
    end);
end;

function TRepositorioMemoria<T>.PorId(AId: Integer): T;
begin
  if not TentarPorId(AId, Result) then
    raise ENaoEncontrado.Create(FNome, AId);
end;

function TRepositorioMemoria<T>.TentarPorId(AId: Integer; out AEntidade: T): Boolean;
begin
  FLock.Enter;
  try
    Result := FItens.TryGetValue(AId, AEntidade);
  finally
    FLock.Leave;
  end;
end;

function TRepositorioMemoria<T>.Existe(AId: Integer): Boolean;
begin
  FLock.Enter;
  try
    Result := FItens.ContainsKey(AId);
  finally
    FLock.Leave;
  end;
end;

function TRepositorioMemoria<T>.TodosSemTrava: TArray<T>;
begin
  Result := FItens.Values.ToArray;
  TArray.Sort<T>(Result, TComparer<T>.Construct(
    function(const A, B: T): Integer
    begin
      Result := A.Id - B.Id;   // ordem estavel e previsivel: por Id
    end));
end;

function TRepositorioMemoria<T>.Todos: TArray<T>;
begin
  FLock.Enter;
  try
    Result := TodosSemTrava;
  finally
    FLock.Leave;
  end;
end;

function TRepositorioMemoria<T>.Buscar(const AEspec: ISpecification<T>): TArray<T>;
var
  LItem: T;
  LLista: TList<T>;
begin
  if AEspec = nil then
    Exit(Todos);

  LLista := TList<T>.Create;
  try
    for LItem in Todos do
      if AEspec.Satisfeita(LItem) then
        LLista.Add(LItem);
    Result := LLista.ToArray;
  finally
    LLista.Free;
  end;
end;

function TRepositorioMemoria<T>.Primeiro(const AEspec: ISpecification<T>): T;
var
  LItem: T;
begin
  for LItem in Todos do
    if (AEspec = nil) or AEspec.Satisfeita(LItem) then
      Exit(LItem);
  Result := nil;
end;

function TRepositorioMemoria<T>.Contar: Integer;
begin
  FLock.Enter;
  try
    Result := FItens.Count;
  finally
    FLock.Leave;
  end;
end;

procedure TRepositorioMemoria<T>.Limpar;
begin
  Travado(
    procedure
    begin
      FItens.Clear;
      FProximoId := 1;
    end);
end;

{ TRepositorioClientes }

function TRepositorioClientes.PorDocumento(const ADocumento: string): TCliente;
var
  LProcurado: string;
  LCliente: TCliente;
begin
  LProcurado := SomenteDigitos(ADocumento);
  for LCliente in Todos do
    if SomenteDigitos(LCliente.Documento) = LProcurado then
      Exit(LCliente);
  Result := nil;
end;

function TRepositorioClientes.PorCategoria(
  ACategoria: TCategoriaCliente): TArray<TCliente>;
var
  LEspec: ISpecification<TCliente>;
begin
  { CUIDADO (armadilha de ARC): NAO escreva
        Buscar(TClienteDaCategoria.Create(ACategoria));
    Parametros "const" de interface nao geram contagem de referencia, entao o
    objeto criado ali ficaria com contador zero e NUNCA seria destruido.
    Guardando na variavel local, o ARC assume e libera ao sair do metodo. }
  LEspec := TClienteDaCategoria.Create(ACategoria);
  Result := Buscar(LEspec);
end;

{ TRepositorioProdutos }

function TRepositorioProdutos.PorCodigo(const ACodigo: string): TProduto;
var
  LProduto: TProduto;
begin
  for LProduto in Todos do
    if SameText(LProduto.Codigo, ACodigo) then
      Exit(LProduto);
  Result := nil;
end;

function TRepositorioProdutos.AbaixoDoMinimo: TArray<TProduto>;
var
  LEspec: ISpecification<TProduto>;
begin
  // Composicao de specifications: ativo E abaixo do minimo
  LEspec := TProdutoAtivo.Create.E(TProdutoAbaixoMinimo.Create);
  Result := Buscar(LEspec);
end;

function TRepositorioProdutos.Categorias: TArray<string>;
var
  LProduto: TProduto;
  LSet: TDictionary<string, Byte>;
begin
  LSet := TDictionary<string, Byte>.Create;
  try
    for LProduto in Todos do
      if LProduto.Categoria <> '' then
        LSet.AddOrSetValue(LProduto.Categoria, 0);
    Result := LSet.Keys.ToArray;
    TArray.Sort<string>(Result);
  finally
    LSet.Free;
  end;
end;

{ TRepositorioPedidos }

function TRepositorioPedidos.PorNumero(const ANumero: string): TPedido;
var
  LPedido: TPedido;
begin
  for LPedido in Todos do
    if SameText(LPedido.Numero, ANumero) then
      Exit(LPedido);
  Result := nil;
end;

function TRepositorioPedidos.DoCliente(AClienteId: Integer): TArray<TPedido>;
var
  LEspec: ISpecification<TPedido>;
begin
  LEspec := TPedidoDoCliente.Create(AClienteId);
  Result := Buscar(LEspec);
end;

function TRepositorioPedidos.ComStatus(const AStatus: TStatusPedidoSet): TArray<TPedido>;
var
  LEspec: ISpecification<TPedido>;
begin
  LEspec := TPedidoComStatus.Create(AStatus);
  Result := Buscar(LEspec);
end;

function TRepositorioPedidos.ProximoNumero: string;
begin
  Result := Format('PED-%.5d', [Contar + 1]);
end;

function TRepositorioPedidos.TotalEmAbertoDoCliente(AClienteId: Integer): Currency;
var
  LPedido: TPedido;
begin
  Result := 0;
  for LPedido in DoCliente(AClienteId) do
    if LPedido.EstaEmAberto then
      Result := Result + LPedido.TotalLiquido;
end;

{ TRepositorioMovimentos }

function TRepositorioMovimentos.DoProduto(
  AProdutoId: Integer): TArray<TMovimentoEstoque>;
var
  LEspec: ISpecification<TMovimentoEstoque>;
begin
  LEspec := TEspecDe<TMovimentoEstoque>.Nova(
    function(const AItem: TMovimentoEstoque): Boolean
    begin
      Result := AItem.ProdutoId = AProdutoId;
    end, 'movimentos do produto');
  Result := Buscar(LEspec);
end;

{ TRepositorioPagamentos }

function TRepositorioPagamentos.DoPedido(APedidoId: Integer): TArray<TPagamento>;
var
  LEspec: ISpecification<TPagamento>;
begin
  LEspec := TEspecDe<TPagamento>.Nova(
    function(const AItem: TPagamento): Boolean
    begin
      Result := AItem.PedidoId = APedidoId;
    end, 'pagamentos do pedido');
  Result := Buscar(LEspec);
end;

{ TRepositorioCentros }

function TRepositorioCentros.PorCodigo(const ACodigo: string): TCentroTrabalho;
var
  LCentro: TCentroTrabalho;
begin
  for LCentro in Todos do
    if SameText(LCentro.Codigo, ACodigo) then
      Exit(LCentro);
  Result := nil;
end;

function TRepositorioCentros.Ativos: TArray<TCentroTrabalho>;
var
  LEspec: ISpecification<TCentroTrabalho>;
begin
  LEspec := TEspecDe<TCentroTrabalho>.Nova(
    function(const AItem: TCentroTrabalho): Boolean
    begin
      Result := AItem.Ativo;
    end, 'centros ativos');
  Result := Buscar(LEspec);
end;

{ TRepositorioEstruturas }

function TRepositorioEstruturas.DoProdutoPai(
  AProdutoPaiId: Integer): TArray<TItemEstrutura>;
var
  LEspec: ISpecification<TItemEstrutura>;
begin
  LEspec := TEspecDe<TItemEstrutura>.Nova(
    function(const AItem: TItemEstrutura): Boolean
    begin
      Result := AItem.ProdutoPaiId = AProdutoPaiId;
    end, 'estrutura do item');
  Result := Buscar(LEspec);
  TArray.Sort<TItemEstrutura>(Result, TComparer<TItemEstrutura>.Construct(
    function(const A, B: TItemEstrutura): Integer
    begin
      Result := A.Sequencia - B.Sequencia;
    end));
end;

function TRepositorioEstruturas.OndeEUsado(
  AComponenteId: Integer): TArray<TItemEstrutura>;
var
  LEspec: ISpecification<TItemEstrutura>;
begin
  LEspec := TEspecDe<TItemEstrutura>.Nova(
    function(const AItem: TItemEstrutura): Boolean
    begin
      Result := AItem.ComponenteId = AComponenteId;
    end, 'onde e usado');
  Result := Buscar(LEspec);
end;

function TRepositorioEstruturas.Linha(AProdutoPaiId,
  AComponenteId: Integer): TItemEstrutura;
var
  LItem: TItemEstrutura;
begin
  for LItem in DoProdutoPai(AProdutoPaiId) do
    if LItem.ComponenteId = AComponenteId then
      Exit(LItem);
  Result := nil;
end;

{ TRepositorioRoteiros }

function TRepositorioRoteiros.DoProduto(
  AProdutoId: Integer): TArray<TOperacaoRoteiro>;
var
  LEspec: ISpecification<TOperacaoRoteiro>;
begin
  LEspec := TEspecDe<TOperacaoRoteiro>.Nova(
    function(const AItem: TOperacaoRoteiro): Boolean
    begin
      Result := AItem.ProdutoId = AProdutoId;
    end, 'roteiro do item');
  Result := Buscar(LEspec);
  // O roteiro SEMPRE sai em ordem de sequencia: e a ordem do processo.
  TArray.Sort<TOperacaoRoteiro>(Result, TComparer<TOperacaoRoteiro>.Construct(
    function(const A, B: TOperacaoRoteiro): Integer
    begin
      Result := A.Sequencia - B.Sequencia;
    end));
end;

function TRepositorioRoteiros.Operacao(AProdutoId,
  ASequencia: Integer): TOperacaoRoteiro;
var
  LItem: TOperacaoRoteiro;
begin
  for LItem in DoProduto(AProdutoId) do
    if LItem.Sequencia = ASequencia then
      Exit(LItem);
  Result := nil;
end;

{ TRepositorioOrdens }

function TRepositorioOrdens.PorNumero(const ANumero: string): TOrdemProducao;
var
  LOrdem: TOrdemProducao;
begin
  for LOrdem in Todos do
    if SameText(LOrdem.Numero, ANumero) then
      Exit(LOrdem);
  Result := nil;
end;

function TRepositorioOrdens.ComStatus(
  const AStatus: TStatusOPSet): TArray<TOrdemProducao>;
var
  LEspec: ISpecification<TOrdemProducao>;
begin
  LEspec := TEspecDe<TOrdemProducao>.Nova(
    function(const AItem: TOrdemProducao): Boolean
    begin
      Result := AItem.Status in AStatus;
    end, 'ordens por status');
  Result := Buscar(LEspec);
end;

function TRepositorioOrdens.DoProduto(
  AProdutoId: Integer): TArray<TOrdemProducao>;
var
  LEspec: ISpecification<TOrdemProducao>;
begin
  LEspec := TEspecDe<TOrdemProducao>.Nova(
    function(const AItem: TOrdemProducao): Boolean
    begin
      Result := AItem.ProdutoId = AProdutoId;
    end, 'ordens do produto');
  Result := Buscar(LEspec);
end;

function TRepositorioOrdens.ProximoNumero: string;
begin
  Result := Format('OP-%.5d', [Contar + 1]);
end;

end.
