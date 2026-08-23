{*******************************************************************************
  Infra.Persistence

  Salva e restaura os repositorios em arquivos JSON.

  ESTUDO:
    * Metodo generico com DUAS restricoes: <T: TEntidade, constructor>
      -> a restricao "constructor" permite escrever T.Create dentro do metodo
    * Polimorfismo na pratica: chamamos AEntidade.ToJson e o Delphi decide, em
      tempo de execucao, se roda a versao generica (RTTI) ou a de TPedido
    * Tratamento de erro em fronteira de I/O: converte qualquer falha em EInfra
*******************************************************************************}
unit Infra.Persistence;

interface

uses
  System.SysUtils,
  System.JSON,
  System.IOUtils,
  Core.Types,
  Core.Json,
  Core.Logger,
  Domain.Entities,
  Domain.Interfaces;

type
  IArmazenamento = interface
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D30}']
    procedure SalvarTudo;
    function CarregarTudo: Boolean;
    function Pasta: string;
    function ExistemDados: Boolean;
    procedure Apagar;
  end;

  TPersistencia = class
  public
    class procedure SalvarRepositorio<T: TEntidade>(const ARepo: IRepositorio<T>;
      const AArquivo: string); static;
    /// Devolve a quantidade de registros carregados.
    class function CarregarRepositorio<T: TEntidade, constructor>(
      const ARepo: IRepositorio<T>; const AArquivo: string): Integer; static;
  end;

  TArmazenamentoJson = class(TInterfacedObject, IArmazenamento)
  private
    FPasta: string;
    FClientes: IRepositorioClientes;
    FProdutos: IRepositorioProdutos;
    FPedidos: IRepositorioPedidos;
    FMovimentos: IRepositorioMovimentos;
    FPagamentos: IRepositorioPagamentos;
    FLogger: ILogger;
    function Arquivo(const ANome: string): string;
  public
    constructor Create(const APasta: string;
      const AClientes: IRepositorioClientes;
      const AProdutos: IRepositorioProdutos;
      const APedidos: IRepositorioPedidos;
      const AMovimentos: IRepositorioMovimentos;
      const APagamentos: IRepositorioPagamentos;
      const ALogger: ILogger);

    procedure SalvarTudo;
    function CarregarTudo: Boolean;
    function Pasta: string;
    function ExistemDados: Boolean;
    procedure Apagar;
  end;

implementation

{ TPersistencia }

class procedure TPersistencia.SalvarRepositorio<T>(const ARepo: IRepositorio<T>;
  const AArquivo: string);
var
  LArray: TJSONArray;
  LEntidade: T;
begin
  LArray := TJSONArray.Create;
  try
    for LEntidade in ARepo.Todos do
      LArray.AddElement(LEntidade.ToJson); // polimorfico!
    TArquivoJson.Salvar(LArray, AArquivo);
  finally
    LArray.Free;  // o array e dono dos objetos que recebeu
  end;
end;

class function TPersistencia.CarregarRepositorio<T>(const ARepo: IRepositorio<T>;
  const AArquivo: string): Integer;
var
  LValor: TJSONValue;
  LElemento: TJSONValue;
  LEntidade: T;
begin
  Result := 0;
  LValor := TArquivoJson.Carregar(AArquivo);
  if LValor = nil then
    Exit;

  try
    if not (LValor is TJSONArray) then
      raise EInfra.CreateFmt('"%s" nao contem uma lista JSON.', [AArquivo]);

    ARepo.Limpar;
    for LElemento in TJSONArray(LValor) do
    begin
      if not (LElemento is TJSONObject) then
        Continue;
      LEntidade := T.Create;   // possivel gracas a restricao "constructor"
      try
        LEntidade.FromJson(TJSONObject(LElemento));
        ARepo.Adicionar(LEntidade);
        Inc(Result);
      except
        LEntidade.Free;
        raise;
      end;
    end;
  finally
    LValor.Free;
  end;
end;

{ TArmazenamentoJson }

constructor TArmazenamentoJson.Create(const APasta: string;
  const AClientes: IRepositorioClientes; const AProdutos: IRepositorioProdutos;
  const APedidos: IRepositorioPedidos; const AMovimentos: IRepositorioMovimentos;
  const APagamentos: IRepositorioPagamentos; const ALogger: ILogger);
begin
  inherited Create;
  FPasta := APasta;
  FClientes := AClientes;
  FProdutos := AProdutos;
  FPedidos := APedidos;
  FMovimentos := AMovimentos;
  FPagamentos := APagamentos;
  if Assigned(ALogger) then
    FLogger := ALogger
  else
    FLogger := TLoggerNulo.Create;
end;

function TArmazenamentoJson.Arquivo(const ANome: string): string;
begin
  Result := TPath.Combine(FPasta, ANome + '.json');
end;

function TArmazenamentoJson.Pasta: string;
begin
  Result := FPasta;
end;

function TArmazenamentoJson.ExistemDados: Boolean;
begin
  Result := TFile.Exists(Arquivo('clientes')) or TFile.Exists(Arquivo('produtos'));
end;

procedure TArmazenamentoJson.SalvarTudo;
begin
  if not TDirectory.Exists(FPasta) then
    TDirectory.CreateDirectory(FPasta);

  TPersistencia.SalvarRepositorio<TCliente>(FClientes, Arquivo('clientes'));
  TPersistencia.SalvarRepositorio<TProduto>(FProdutos, Arquivo('produtos'));
  TPersistencia.SalvarRepositorio<TPedido>(FPedidos, Arquivo('pedidos'));
  TPersistencia.SalvarRepositorio<TMovimentoEstoque>(FMovimentos, Arquivo('movimentos'));
  TPersistencia.SalvarRepositorio<TPagamento>(FPagamentos, Arquivo('pagamentos'));

  FLogger.Info('Dados salvos em "%s" (%d clientes, %d produtos, %d pedidos).',
    [FPasta, FClientes.Contar, FProdutos.Contar, FPedidos.Contar]);
end;

function TArmazenamentoJson.CarregarTudo: Boolean;
var
  LTotal: Integer;
begin
  if not ExistemDados then
    Exit(False);

  LTotal := 0;
  Inc(LTotal, TPersistencia.CarregarRepositorio<TCliente>(FClientes, Arquivo('clientes')));
  Inc(LTotal, TPersistencia.CarregarRepositorio<TProduto>(FProdutos, Arquivo('produtos')));
  Inc(LTotal, TPersistencia.CarregarRepositorio<TPedido>(FPedidos, Arquivo('pedidos')));
  Inc(LTotal, TPersistencia.CarregarRepositorio<TMovimentoEstoque>(FMovimentos, Arquivo('movimentos')));
  Inc(LTotal, TPersistencia.CarregarRepositorio<TPagamento>(FPagamentos, Arquivo('pagamentos')));

  FLogger.Info('Dados carregados de "%s": %d registro(s).', [FPasta, LTotal]);
  Result := LTotal > 0;
end;

procedure TArmazenamentoJson.Apagar;
var
  LNome: string;
begin
  for LNome in TArray<string>.Create('clientes', 'produtos', 'pedidos',
    'movimentos', 'pagamentos') do
    if TFile.Exists(Arquivo(LNome)) then
      TFile.Delete(Arquivo(LNome));
  FLogger.Aviso('Arquivos de dados apagados de "%s".', [FPasta]);
end;

end.
