{*******************************************************************************
  Infra.Repositories.Firebird

  Os MESMOS contratos de Domain.Interfaces, agora gravando em Firebird.
  Nenhuma linha do dominio muda: e so registrar estes no lugar dos de memoria
  (ver App.Bootstrap). Esse e o teste definitivo da arquitetura.

  DOIS PADROES DE ORM APARECEM AQUI:

  1) DATA MAPPER
     A classe nao sabe se gravar. O mapeador (Infra.Mapping) le o RTTI e monta
     o SQL. O oposto seria "Active Record", em que TProduto teria Salvar/Excluir
     - pratico, mas amarra o dominio ao banco.

  2) IDENTITY MAP  <-- o mais importante de entender aqui
     Um mesmo registro do banco deve virar UM UNICO objeto em memoria.
     Sem isso, "PorId(7)" devolveria um objeto novo a cada chamada e:
        - quem alterasse um deles nao veria a alteracao no outro
        - ninguem saberia quem destroi cada instancia (vazamento na certa)
     Com o mapa de identidade o repositorio vira o DONO dos objetos, e o
     comportamento fica identico ao repositorio em memoria - por isso os
     servicos de dominio funcionam nos dois sem alteracao.

     Limite honesto: este cache e por instancia de repositorio e nao percebe
     alteracoes feitas por OUTRA aplicacao. Serve para estudo e monousuario;
     um ERP multiusuario precisa de recarga/versionamento (veja os exercicios).

  3) AGREGADOS
     Pedido tem itens; ordem de producao tem componentes, operacoes e
     apontamentos. A estrategia aqui e a mais simples que funciona:
     ao salvar o pai, apaga os filhos e regrava. Documentado como tal.
*******************************************************************************}
unit Infra.Repositories.Firebird;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Variants,
  System.Rtti,
  System.TypInfo,
  System.Generics.Collections,
  System.Generics.Defaults,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  Core.Types,
  Core.Logger,
  Domain.Entities,
  Domain.Enums,
  Domain.Interfaces,
  Domain.Producao,
  Domain.Specifications,
  Infra.Database,
  Infra.Mapping;

type
  /// Converte propriedade <-> campo/parametro usando RTTI.
  TMapeadorRegistro = class
  public
    class procedure ParaParametros(AEntidade: TObject; AMapa: TMapaTabela;
      AQuery: TFDQuery); static;
    class procedure DoRegistro(AEntidade: TObject; AMapa: TMapaTabela;
      AQuery: TFDQuery); static;
  end;

  TRepositorioFirebird<T: TEntidade, constructor> = class(TInterfacedObject,
    IRepositorio<T>)
  private
    FConexao: IConexaoBanco;
    FMapa: TMapaTabela;
    FCache: TObjectDictionary<Integer, T>;   // IDENTITY MAP (dono dos objetos)
    FNome: string;
    function Materializar(AQuery: TFDQuery): T;
  protected
    /// Ganchos de agregado (Template Method).
    procedure CarregarFilhos(AEntidade: T); virtual;
    procedure SalvarFilhos(AEntidade: T); virtual;
    function ClausulaOrdem: string; virtual;

    /// Auxiliares para as filhas gravarem/lerem colecoes.
    procedure GravarColecao(AClasseFilho: TClass; const ACampoPai: string;
      AIdPai: Integer; const AFilhos: array of TEntidade);
    procedure LerColecao(AClasseFilho: TClass; const ACampoPai: string;
      AIdPai: Integer; const ACriar: TFunc<TEntidade>;
      const AAdicionar: TProc<TEntidade>; const AOrdem: string = '');

    function CarregarPorSql(const AComplemento: string;
      const AParams: array of Variant): TArray<T>;

    property Conexao: IConexaoBanco read FConexao;
    property Mapa: TMapaTabela read FMapa;
  public
    constructor Create(const AConexao: IConexaoBanco);
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

  { ------------------------- repositorios concretos ------------------------- }

  TRepositorioClientesFB = class(TRepositorioFirebird<TCliente>,
    IRepositorioClientes)
  public
    function PorDocumento(const ADocumento: string): TCliente;
    function PorCategoria(ACategoria: TCategoriaCliente): TArray<TCliente>;
  end;

  TRepositorioProdutosFB = class(TRepositorioFirebird<TProduto>,
    IRepositorioProdutos)
  public
    function PorCodigo(const ACodigo: string): TProduto;
    function AbaixoDoMinimo: TArray<TProduto>;
    function Categorias: TArray<string>;
  end;

  TRepositorioPedidosFB = class(TRepositorioFirebird<TPedido>,
    IRepositorioPedidos)
  protected
    procedure CarregarFilhos(AEntidade: TPedido); override;
    procedure SalvarFilhos(AEntidade: TPedido); override;
  public
    function PorNumero(const ANumero: string): TPedido;
    function DoCliente(AClienteId: Integer): TArray<TPedido>;
    function ComStatus(const AStatus: TStatusPedidoSet): TArray<TPedido>;
    function ProximoNumero: string;
    function TotalEmAbertoDoCliente(AClienteId: Integer): Currency;
  end;

  TRepositorioMovimentosFB = class(TRepositorioFirebird<TMovimentoEstoque>,
    IRepositorioMovimentos)
  public
    function DoProduto(AProdutoId: Integer): TArray<TMovimentoEstoque>;
  end;

  TRepositorioPagamentosFB = class(TRepositorioFirebird<TPagamento>,
    IRepositorioPagamentos)
  public
    function DoPedido(APedidoId: Integer): TArray<TPagamento>;
  end;

  TRepositorioCentrosFB = class(TRepositorioFirebird<TCentroTrabalho>,
    IRepositorioCentros)
  public
    function PorCodigo(const ACodigo: string): TCentroTrabalho;
    function Ativos: TArray<TCentroTrabalho>;
  end;

  TRepositorioEstruturasFB = class(TRepositorioFirebird<TItemEstrutura>,
    IRepositorioEstruturas)
  protected
    function ClausulaOrdem: string; override;
  public
    function DoProdutoPai(AProdutoPaiId: Integer): TArray<TItemEstrutura>;
    function OndeEUsado(AComponenteId: Integer): TArray<TItemEstrutura>;
    function Linha(AProdutoPaiId, AComponenteId: Integer): TItemEstrutura;
  end;

  TRepositorioRoteirosFB = class(TRepositorioFirebird<TOperacaoRoteiro>,
    IRepositorioRoteiros)
  protected
    function ClausulaOrdem: string; override;
  public
    function DoProduto(AProdutoId: Integer): TArray<TOperacaoRoteiro>;
    function Operacao(AProdutoId, ASequencia: Integer): TOperacaoRoteiro;
  end;

  TRepositorioOrdensFB = class(TRepositorioFirebird<TOrdemProducao>,
    IRepositorioOrdens)
  protected
    procedure CarregarFilhos(AEntidade: TOrdemProducao); override;
    procedure SalvarFilhos(AEntidade: TOrdemProducao); override;
  public
    function PorNumero(const ANumero: string): TOrdemProducao;
    function ComStatus(const AStatus: TStatusOPSet): TArray<TOrdemProducao>;
    function DoProduto(AProdutoId: Integer): TArray<TOrdemProducao>;
    function ProximoNumero: string;
  end;

/// Registra o mapeamento de TODAS as entidades. Chamar uma vez no bootstrap.
procedure RegistrarMapeamentos;

implementation

{ --------------------------------------------------------------------------
  Mapeamento (tabela + colunas ignoradas) de cada entidade.
  Tudo que e calculado ou colecao entra na lista de ignorados.
  -------------------------------------------------------------------------- }
procedure RegistrarMapeamentos;

  function Novo(AClasse: TClass; const ATabela, AGenerator: string;
    const AIgnorar: array of string): TMapaTabela;
  begin
    Result := TMapaTabela.Create(AClasse, ATabela, AGenerator);
    Result.MapearAutomatico(AIgnorar);
    TMapeamento.Registrar(Result);
  end;

begin
  if TMapeamento.Existe(TCliente) then
    Exit;   // ja registrado

  Novo(TCliente, 'CLIENTES', 'GEN_CLIENTES_ID', []);
  Novo(TProduto, 'PRODUTOS', 'GEN_PRODUTOS_ID', []);
  Novo(TPedido, 'PEDIDOS', 'GEN_PEDIDOS_ID', []);
  Novo(TItemPedido, 'PEDIDO_ITENS', 'GEN_PEDIDO_ITENS_ID', []);
  Novo(TMovimentoEstoque, 'MOVIMENTOS_ESTOQUE', 'GEN_MOVIMENTOS_ID', []);
  Novo(TPagamento, 'PAGAMENTOS', 'GEN_PAGAMENTOS_ID', []);

  Novo(TCentroTrabalho, 'CENTROS_TRABALHO', 'GEN_CENTROS_ID', []);
  Novo(TItemEstrutura, 'ESTRUTURA_ITENS', 'GEN_ESTRUTURA_ID', []);
  Novo(TOperacaoRoteiro, 'ROTEIRO_OPERACOES', 'GEN_ROTEIRO_ID', []);
  Novo(TOrdemProducao, 'ORDENS_PRODUCAO', 'GEN_ORDENS_ID', []);
  Novo(TComponenteOP, 'OP_COMPONENTES', 'GEN_OP_COMPONENTES_ID', []);
  Novo(TOperacaoOP, 'OP_OPERACOES', 'GEN_OP_OPERACOES_ID', []);
  Novo(TApontamento, 'OP_APONTAMENTOS', 'GEN_OP_APONTAMENTOS_ID', []);
end;

{ TMapeadorRegistro }

class procedure TMapeadorRegistro.ParaParametros(AEntidade: TObject;
  AMapa: TMapaTabela; AQuery: TFDQuery);
var
  LCtx: TRttiContext;
  LTipo: TRttiType;
  LProp: TRttiProperty;
  LColuna: TMapaColuna;
  LValor: TValue;
  LParam: TFDParam;
  LData: TDateTime;
begin
  LCtx := TRttiContext.Create;
  try
    LTipo := LCtx.GetType(AEntidade.ClassType);
    for LColuna in AMapa.Colunas do
    begin
      LParam := AQuery.Params.FindParam(LColuna.Coluna);
      if LParam = nil then
        Continue;

      LProp := LTipo.GetProperty(LColuna.Propriedade);
      if LProp = nil then
        Continue;

      LValor := LProp.GetValue(AEntidade);

      case LProp.PropertyType.TypeKind of
        tkInteger, tkInt64:
          LParam.AsLargeInt := LValor.AsInt64;

        tkFloat:
          if LProp.PropertyType.Handle = TypeInfo(TDateTime) then
          begin
            LData := LValor.AsType<TDateTime>;
            // Data zerada vira NULL: no banco "sem data" e NULL, nao 30/12/1899.
            if LData = 0 then
              LParam.Clear
            else
              LParam.AsDateTime := LData;
          end
          else if LProp.PropertyType.Handle = TypeInfo(Currency) then
            LParam.AsCurrency := LValor.AsType<Currency>
          else
            LParam.AsFloat := LValor.AsExtended;

        tkEnumeration:
          if LProp.PropertyType.Handle = TypeInfo(Boolean) then
            LParam.AsBoolean := LValor.AsBoolean
          else
            // Enum vira o NOME RTTI: legivel no banco e imune a reordenacao.
            LParam.AsString := GetEnumName(LProp.PropertyType.Handle,
              LValor.AsOrdinal);
      else
        LParam.AsString := LValor.AsString;
      end;
    end;
  finally
    LCtx.Free;
  end;
end;

class procedure TMapeadorRegistro.DoRegistro(AEntidade: TObject;
  AMapa: TMapaTabela; AQuery: TFDQuery);
var
  LCtx: TRttiContext;
  LTipo: TRttiType;
  LProp: TRttiProperty;
  LColuna: TMapaColuna;
  LCampo: TField;
  LOrdinal: Integer;
begin
  LCtx := TRttiContext.Create;
  try
    LTipo := LCtx.GetType(AEntidade.ClassType);
    for LColuna in AMapa.Colunas do
    begin
      LCampo := AQuery.FindField(LColuna.Coluna);
      if LCampo = nil then
        Continue;

      LProp := LTipo.GetProperty(LColuna.Propriedade);
      if (LProp = nil) or (not LProp.IsWritable) then
        Continue;

      case LProp.PropertyType.TypeKind of
        tkInteger:
          LProp.SetValue(AEntidade, LCampo.AsInteger);
        tkInt64:
          LProp.SetValue(AEntidade, LCampo.AsLargeInt);

        tkFloat:
          if LProp.PropertyType.Handle = TypeInfo(TDateTime) then
          begin
            if LCampo.IsNull then
              LProp.SetValue(AEntidade, TValue.From<TDateTime>(0))
            else
              LProp.SetValue(AEntidade, TValue.From<TDateTime>(LCampo.AsDateTime));
          end
          else if LProp.PropertyType.Handle = TypeInfo(Currency) then
            LProp.SetValue(AEntidade, TValue.From<Currency>(LCampo.AsCurrency))
          else
            LProp.SetValue(AEntidade, TValue.From<Double>(LCampo.AsFloat));

        tkEnumeration:
          if LProp.PropertyType.Handle = TypeInfo(Boolean) then
            LProp.SetValue(AEntidade, LCampo.AsBoolean)
          else
          begin
            LOrdinal := GetEnumValue(LProp.PropertyType.Handle,
              Trim(LCampo.AsString));
            if LOrdinal >= 0 then
              LProp.SetValue(AEntidade,
                TValue.FromOrdinal(LProp.PropertyType.Handle, LOrdinal));
          end;
      else
        LProp.SetValue(AEntidade, LCampo.AsString);
      end;
    end;
  finally
    LCtx.Free;
  end;
end;

{ TRepositorioFirebird<T> }

constructor TRepositorioFirebird<T>.Create(const AConexao: IConexaoBanco);
var
  LCtx: TRttiContext;
  LTipo: TRttiInstanceType;
begin
  inherited Create;
  FConexao := AConexao;
  FCache := TObjectDictionary<Integer, T>.Create([doOwnsValues]);

  LCtx := TRttiContext.Create;
  try
    LTipo := LCtx.GetType(TypeInfo(T)) as TRttiInstanceType;
    FNome := LTipo.MetaclassType.ClassName;
    FMapa := TMapeamento.Para(LTipo.MetaclassType);
  finally
    LCtx.Free;
  end;
end;

destructor TRepositorioFirebird<T>.Destroy;
begin
  FCache.Free;   // o repositorio e o dono das entidades carregadas
  inherited;
end;

function TRepositorioFirebird<T>.NomeEntidade: string;
begin
  Result := FNome;
end;

function TRepositorioFirebird<T>.ClausulaOrdem: string;
begin
  Result := ' ORDER BY ' + FMapa.ColunaChave;
end;

procedure TRepositorioFirebird<T>.CarregarFilhos(AEntidade: T);
begin
  // entidades simples nao tem filhos
end;

procedure TRepositorioFirebird<T>.SalvarFilhos(AEntidade: T);
begin
  // idem
end;

function TRepositorioFirebird<T>.Materializar(AQuery: TFDQuery): T;
var
  LId: Integer;
  LExistente: T;
begin
  LId := AQuery.FieldByName(FMapa.ColunaChave).AsInteger;

  { IDENTITY MAP: se este registro ja virou objeto, devolvemos o MESMO.
    Nao sobrescrevemos os campos: alteracoes ainda nao gravadas seriam
    perdidas silenciosamente - o pior tipo de bug. }
  if FCache.TryGetValue(LId, LExistente) then
    Exit(LExistente);

  Result := T.Create;
  try
    TMapeadorRegistro.DoRegistro(Result, FMapa, AQuery);
    FCache.Add(LId, Result);
  except
    Result.Free;
    raise;
  end;
  CarregarFilhos(Result);
end;

function TRepositorioFirebird<T>.CarregarPorSql(const AComplemento: string;
  const AParams: array of Variant): TArray<T>;
var
  LQuery: TFDQuery;
  LLista: TList<T>;
  I: Integer;
begin
  LLista := TList<T>.Create;
  LQuery := FConexao.NovaQuery;
  try
    LQuery.SQL.Text := FMapa.SqlSelect + AComplemento;
    for I := 0 to High(AParams) do
      if I < LQuery.Params.Count then
        LQuery.Params[I].Value := AParams[I];
    LQuery.Open;

    while not LQuery.Eof do
    begin
      LLista.Add(Materializar(LQuery));
      LQuery.Next;
    end;
    Result := LLista.ToArray;
  finally
    LQuery.Free;
    LLista.Free;
  end;
end;

function TRepositorioFirebird<T>.Adicionar(AEntidade: T): T;
var
  LQuery: TFDQuery;
  LExistente: T;
begin
  if AEntidade = nil then
    raise EDominio.Create('Tentativa de adicionar entidade nula.');

  if AEntidade.Id = 0 then
    AEntidade.Id := FConexao.ProximoId(FMapa.Generator);

  LQuery := FConexao.NovaQuery;
  try
    LQuery.SQL.Text := FMapa.SqlInsert;
    TMapeadorRegistro.ParaParametros(AEntidade, FMapa, LQuery);
    try
      LQuery.ExecSQL;
    except
      on E: Exception do
        raise EInfra.CreateFmt('Falha ao inserir em %s (Id %d): %s',
          [FMapa.Tabela, AEntidade.Id, E.Message]);
    end;
  finally
    LQuery.Free;
  end;

  SalvarFilhos(AEntidade);

  // Entra no mapa de identidade (cuidando de nao destruir a si mesma).
  if FCache.TryGetValue(AEntidade.Id, LExistente) then
  begin
    if TObject(LExistente) <> TObject(AEntidade) then
      FCache.AddOrSetValue(AEntidade.Id, AEntidade);
  end
  else
    FCache.Add(AEntidade.Id, AEntidade);

  Result := AEntidade;
end;

procedure TRepositorioFirebird<T>.Atualizar(AEntidade: T);
var
  LQuery: TFDQuery;
  LAfetadas: Integer;
begin
  if AEntidade = nil then
    raise EDominio.Create('Tentativa de atualizar entidade nula.');

  AEntidade.MarcarAtualizado;

  LQuery := FConexao.NovaQuery;
  try
    LQuery.SQL.Text := FMapa.SqlUpdate;
    TMapeadorRegistro.ParaParametros(AEntidade, FMapa, LQuery);
    LQuery.ExecSQL;
    LAfetadas := LQuery.RowsAffected;
  finally
    LQuery.Free;
  end;

  if LAfetadas = 0 then
    raise ENaoEncontrado.Create(FNome, AEntidade.Id);

  SalvarFilhos(AEntidade);
end;

procedure TRepositorioFirebird<T>.Remover(AId: Integer);
var
  LAfetadas: Integer;
begin
  // Os filhos saem por ON DELETE CASCADE (ver bd/schema.sql).
  LAfetadas := FConexao.Executar(FMapa.SqlDelete, [AId]);
  if LAfetadas = 0 then
    raise ENaoEncontrado.Create(FNome, AId);
  FCache.Remove(AId);   // doOwnsValues destroi o objeto
end;

function TRepositorioFirebird<T>.PorId(AId: Integer): T;
begin
  if not TentarPorId(AId, Result) then
    raise ENaoEncontrado.Create(FNome, AId);
end;

function TRepositorioFirebird<T>.TentarPorId(AId: Integer; out AEntidade: T): Boolean;
var
  LQuery: TFDQuery;
begin
  if FCache.TryGetValue(AId, AEntidade) then
    Exit(True);

  LQuery := FConexao.NovaQuery;
  try
    LQuery.SQL.Text := FMapa.SqlSelectPorId;
    LQuery.Params[0].AsInteger := AId;
    LQuery.Open;
    if LQuery.IsEmpty then
    begin
      AEntidade := nil;
      Exit(False);
    end;
    AEntidade := Materializar(LQuery);
    Result := True;
  finally
    LQuery.Free;
  end;
end;

function TRepositorioFirebird<T>.Existe(AId: Integer): Boolean;
begin
  Result := FCache.ContainsKey(AId) or
            (not VarIsNull(FConexao.ValorEscalar(FMapa.SqlExiste, [AId])));
end;

function TRepositorioFirebird<T>.Todos: TArray<T>;
begin
  Result := CarregarPorSql(ClausulaOrdem, []);
end;

function TRepositorioFirebird<T>.Buscar(const AEspec: ISpecification<T>): TArray<T>;
var
  LItem: T;
  LLista: TList<T>;
begin
  { Filtro em memoria. Traduzir specification para WHERE seria mais rapido,
    mas exigiria um tradutor de expressoes - fica como exercicio no README.
    Para consultas quentes, os repositorios concretos usam SQL direto. }
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

function TRepositorioFirebird<T>.Primeiro(const AEspec: ISpecification<T>): T;
var
  LItem: T;
begin
  for LItem in Todos do
    if (AEspec = nil) or AEspec.Satisfeita(LItem) then
      Exit(LItem);
  Result := nil;
end;

function TRepositorioFirebird<T>.Contar: Integer;
var
  LValor: Variant;
begin
  LValor := FConexao.ValorEscalar(FMapa.SqlContar, []);
  if VarIsNull(LValor) then
    Result := 0
  else
    Result := LValor;
end;

procedure TRepositorioFirebird<T>.Limpar;
begin
  FConexao.Executar(FMapa.SqlApagarTudo, []);
  FCache.Clear;
end;

procedure TRepositorioFirebird<T>.GravarColecao(AClasseFilho: TClass;
  const ACampoPai: string; AIdPai: Integer; const AFilhos: array of TEntidade);
var
  LMapaFilho: TMapaTabela;
  LQuery: TFDQuery;
  LFilho: TEntidade;
begin
  LMapaFilho := TMapeamento.Para(AClasseFilho);

  { Estrategia "apaga e regrava": simples e sempre correta. O preco e que os
    Ids dos filhos mudam a cada gravacao do pai. Para um ERP de verdade,
    o certo seria comparar e aplicar so as diferencas. }
  FConexao.Executar(Format('DELETE FROM %s WHERE %s = :P',
    [LMapaFilho.Tabela, ACampoPai]), [AIdPai]);

  if Length(AFilhos) = 0 then
    Exit;

  LQuery := FConexao.NovaQuery;
  try
    LQuery.SQL.Text := LMapaFilho.SqlInsert;
    for LFilho in AFilhos do
    begin
      LFilho.Id := FConexao.ProximoId(LMapaFilho.Generator);
      TMapeadorRegistro.ParaParametros(LFilho, LMapaFilho, LQuery);
      LQuery.ExecSQL;
    end;
  finally
    LQuery.Free;
  end;
end;

procedure TRepositorioFirebird<T>.LerColecao(AClasseFilho: TClass;
  const ACampoPai: string; AIdPai: Integer; const ACriar: TFunc<TEntidade>;
  const AAdicionar: TProc<TEntidade>; const AOrdem: string);
var
  LMapaFilho: TMapaTabela;
  LQuery: TFDQuery;
  LFilho: TEntidade;
begin
  LMapaFilho := TMapeamento.Para(AClasseFilho);
  LQuery := FConexao.NovaQuery;
  try
    LQuery.SQL.Text := Format('%s WHERE %s = :P%s',
      [LMapaFilho.SqlSelect, ACampoPai, AOrdem]);
    LQuery.Params[0].AsInteger := AIdPai;
    LQuery.Open;

    while not LQuery.Eof do
    begin
      LFilho := ACriar();
      try
        TMapeadorRegistro.DoRegistro(LFilho, LMapaFilho, LQuery);
        AAdicionar(LFilho);
      except
        LFilho.Free;
        raise;
      end;
      LQuery.Next;
    end;
  finally
    LQuery.Free;
  end;
end;

{ ============================ CLIENTES ============================ }

function TRepositorioClientesFB.PorDocumento(const ADocumento: string): TCliente;
var
  LEncontrados: TArray<TCliente>;
begin
  LEncontrados := CarregarPorSql(' WHERE DOCUMENTO = :D', [ADocumento]);
  if Length(LEncontrados) = 0 then
    Exit(nil);
  Result := LEncontrados[0];
end;

function TRepositorioClientesFB.PorCategoria(
  ACategoria: TCategoriaCliente): TArray<TCliente>;
begin
  Result := CarregarPorSql(' WHERE CATEGORIA = :C ORDER BY ID',
    [GetEnumName(TypeInfo(TCategoriaCliente), Ord(ACategoria))]);
end;

{ ============================ PRODUTOS ============================ }

function TRepositorioProdutosFB.PorCodigo(const ACodigo: string): TProduto;
var
  LEncontrados: TArray<TProduto>;
begin
  LEncontrados := CarregarPorSql(' WHERE UPPER(CODIGO) = :C',
    [UpperCase(ACodigo)]);
  if Length(LEncontrados) = 0 then
    Exit(nil);
  Result := LEncontrados[0];
end;

function TRepositorioProdutosFB.AbaixoDoMinimo: TArray<TProduto>;
begin
  // Aqui vale SQL direto: o banco filtra muito melhor que nos.
  Result := CarregarPorSql(
    ' WHERE ATIVO = TRUE AND ESTOQUE < ESTOQUEMINIMO ORDER BY CODIGO', []);
end;

function TRepositorioProdutosFB.Categorias: TArray<string>;
var
  LQuery: TFDQuery;
  LLista: TList<string>;
begin
  LLista := TList<string>.Create;
  LQuery := Conexao.NovaQuery;
  try
    LQuery.SQL.Text := 'SELECT DISTINCT CATEGORIA FROM PRODUTOS ' +
      'WHERE CATEGORIA IS NOT NULL AND CATEGORIA <> '''' ORDER BY 1';
    LQuery.Open;
    while not LQuery.Eof do
    begin
      LLista.Add(LQuery.Fields[0].AsString);
      LQuery.Next;
    end;
    Result := LLista.ToArray;
  finally
    LQuery.Free;
    LLista.Free;
  end;
end;

{ ============================= PEDIDOS ============================= }

procedure TRepositorioPedidosFB.CarregarFilhos(AEntidade: TPedido);
begin
  AEntidade.Itens.Clear;
  LerColecao(TItemPedido, 'PEDIDOID', AEntidade.Id,
    function: TEntidade
    begin
      Result := TItemPedido.Create;
    end,
    procedure(AFilho: TEntidade)
    begin
      AEntidade.Itens.Add(TItemPedido(AFilho));
    end,
    ' ORDER BY ID');
end;

procedure TRepositorioPedidosFB.SalvarFilhos(AEntidade: TPedido);
var
  LFilhos: TArray<TEntidade>;
  I: Integer;
begin
  SetLength(LFilhos, AEntidade.Itens.Count);
  for I := 0 to AEntidade.Itens.Count - 1 do
  begin
    AEntidade.Itens[I].PedidoId := AEntidade.Id;   // a chave estrangeira
    LFilhos[I] := AEntidade.Itens[I];
  end;
  GravarColecao(TItemPedido, 'PEDIDOID', AEntidade.Id, LFilhos);
end;

function TRepositorioPedidosFB.PorNumero(const ANumero: string): TPedido;
var
  LEncontrados: TArray<TPedido>;
begin
  LEncontrados := CarregarPorSql(' WHERE NUMERO = :N', [ANumero]);
  if Length(LEncontrados) = 0 then
    Exit(nil);
  Result := LEncontrados[0];
end;

function TRepositorioPedidosFB.DoCliente(AClienteId: Integer): TArray<TPedido>;
begin
  Result := CarregarPorSql(' WHERE CLIENTEID = :C ORDER BY ID', [AClienteId]);
end;

function TRepositorioPedidosFB.ComStatus(
  const AStatus: TStatusPedidoSet): TArray<TPedido>;
var
  LEspec: ISpecification<TPedido>;
begin
  LEspec := TPedidoComStatus.Create(AStatus);
  Result := Buscar(LEspec);
end;

function TRepositorioPedidosFB.ProximoNumero: string;
begin
  Result := Format('PED-%.5d', [Contar + 1]);
end;

function TRepositorioPedidosFB.TotalEmAbertoDoCliente(
  AClienteId: Integer): Currency;
var
  LPedido: TPedido;
begin
  Result := 0;
  for LPedido in DoCliente(AClienteId) do
    if LPedido.EstaEmAberto then
      Result := Result + LPedido.TotalLiquido;
end;

{ =========================== MOVIMENTOS =========================== }

function TRepositorioMovimentosFB.DoProduto(
  AProdutoId: Integer): TArray<TMovimentoEstoque>;
begin
  Result := CarregarPorSql(' WHERE PRODUTOID = :P ORDER BY ID', [AProdutoId]);
end;

{ =========================== PAGAMENTOS =========================== }

function TRepositorioPagamentosFB.DoPedido(
  APedidoId: Integer): TArray<TPagamento>;
begin
  Result := CarregarPorSql(' WHERE PEDIDOID = :P ORDER BY ID', [APedidoId]);
end;

{ ============================= CENTROS ============================= }

function TRepositorioCentrosFB.PorCodigo(const ACodigo: string): TCentroTrabalho;
var
  LEncontrados: TArray<TCentroTrabalho>;
begin
  LEncontrados := CarregarPorSql(' WHERE UPPER(CODIGO) = :C',
    [UpperCase(ACodigo)]);
  if Length(LEncontrados) = 0 then
    Exit(nil);
  Result := LEncontrados[0];
end;

function TRepositorioCentrosFB.Ativos: TArray<TCentroTrabalho>;
begin
  Result := CarregarPorSql(' WHERE ATIVO = TRUE ORDER BY CODIGO', []);
end;

{ ============================ ESTRUTURA ============================ }

function TRepositorioEstruturasFB.ClausulaOrdem: string;
begin
  Result := ' ORDER BY PRODUTOPAIID, SEQUENCIA';
end;

function TRepositorioEstruturasFB.DoProdutoPai(
  AProdutoPaiId: Integer): TArray<TItemEstrutura>;
begin
  Result := CarregarPorSql(' WHERE PRODUTOPAIID = :P ORDER BY SEQUENCIA',
    [AProdutoPaiId]);
end;

function TRepositorioEstruturasFB.OndeEUsado(
  AComponenteId: Integer): TArray<TItemEstrutura>;
begin
  Result := CarregarPorSql(' WHERE COMPONENTEID = :C ORDER BY PRODUTOPAIID',
    [AComponenteId]);
end;

function TRepositorioEstruturasFB.Linha(AProdutoPaiId,
  AComponenteId: Integer): TItemEstrutura;
var
  LEncontrados: TArray<TItemEstrutura>;
begin
  LEncontrados := CarregarPorSql(
    ' WHERE PRODUTOPAIID = :P AND COMPONENTEID = :C',
    [AProdutoPaiId, AComponenteId]);
  if Length(LEncontrados) = 0 then
    Exit(nil);
  Result := LEncontrados[0];
end;

{ ============================= ROTEIRO ============================= }

function TRepositorioRoteirosFB.ClausulaOrdem: string;
begin
  Result := ' ORDER BY PRODUTOID, SEQUENCIA';
end;

function TRepositorioRoteirosFB.DoProduto(
  AProdutoId: Integer): TArray<TOperacaoRoteiro>;
begin
  Result := CarregarPorSql(' WHERE PRODUTOID = :P ORDER BY SEQUENCIA',
    [AProdutoId]);
end;

function TRepositorioRoteirosFB.Operacao(AProdutoId,
  ASequencia: Integer): TOperacaoRoteiro;
var
  LEncontrados: TArray<TOperacaoRoteiro>;
begin
  LEncontrados := CarregarPorSql(
    ' WHERE PRODUTOID = :P AND SEQUENCIA = :S', [AProdutoId, ASequencia]);
  if Length(LEncontrados) = 0 then
    Exit(nil);
  Result := LEncontrados[0];
end;

{ ======================== ORDENS DE PRODUCAO ======================== }

procedure TRepositorioOrdensFB.CarregarFilhos(AEntidade: TOrdemProducao);
begin
  AEntidade.Componentes.Clear;
  LerColecao(TComponenteOP, 'ORDEMID', AEntidade.Id,
    function: TEntidade
    begin
      Result := TComponenteOP.Create;
    end,
    procedure(AFilho: TEntidade)
    begin
      AEntidade.Componentes.Add(TComponenteOP(AFilho));
    end,
    ' ORDER BY ID');

  AEntidade.Operacoes.Clear;
  LerColecao(TOperacaoOP, 'ORDEMID', AEntidade.Id,
    function: TEntidade
    begin
      Result := TOperacaoOP.Create;
    end,
    procedure(AFilho: TEntidade)
    begin
      AEntidade.Operacoes.Add(TOperacaoOP(AFilho));
    end,
    ' ORDER BY SEQUENCIA');   // o roteiro sempre em ordem de processo

  AEntidade.Apontamentos.Clear;
  LerColecao(TApontamento, 'ORDEMID', AEntidade.Id,
    function: TEntidade
    begin
      Result := TApontamento.Create;
    end,
    procedure(AFilho: TEntidade)
    begin
      AEntidade.Apontamentos.Add(TApontamento(AFilho));
    end,
    ' ORDER BY ID');
end;

procedure TRepositorioOrdensFB.SalvarFilhos(AEntidade: TOrdemProducao);
var
  LFilhos: TArray<TEntidade>;
  I: Integer;
begin
  SetLength(LFilhos, AEntidade.Componentes.Count);
  for I := 0 to AEntidade.Componentes.Count - 1 do
  begin
    AEntidade.Componentes[I].OrdemId := AEntidade.Id;
    LFilhos[I] := AEntidade.Componentes[I];
  end;
  GravarColecao(TComponenteOP, 'ORDEMID', AEntidade.Id, LFilhos);

  SetLength(LFilhos, AEntidade.Operacoes.Count);
  for I := 0 to AEntidade.Operacoes.Count - 1 do
  begin
    AEntidade.Operacoes[I].OrdemId := AEntidade.Id;
    LFilhos[I] := AEntidade.Operacoes[I];
  end;
  GravarColecao(TOperacaoOP, 'ORDEMID', AEntidade.Id, LFilhos);

  SetLength(LFilhos, AEntidade.Apontamentos.Count);
  for I := 0 to AEntidade.Apontamentos.Count - 1 do
  begin
    AEntidade.Apontamentos[I].OrdemId := AEntidade.Id;
    LFilhos[I] := AEntidade.Apontamentos[I];
  end;
  GravarColecao(TApontamento, 'ORDEMID', AEntidade.Id, LFilhos);
end;

function TRepositorioOrdensFB.PorNumero(const ANumero: string): TOrdemProducao;
var
  LEncontrados: TArray<TOrdemProducao>;
begin
  LEncontrados := CarregarPorSql(' WHERE NUMERO = :N', [ANumero]);
  if Length(LEncontrados) = 0 then
    Exit(nil);
  Result := LEncontrados[0];
end;

function TRepositorioOrdensFB.ComStatus(
  const AStatus: TStatusOPSet): TArray<TOrdemProducao>;
var
  LTodas: TArray<TOrdemProducao>;
  LOrdem: TOrdemProducao;
  LLista: TList<TOrdemProducao>;
begin
  LLista := TList<TOrdemProducao>.Create;
  try
    LTodas := Todos;
    for LOrdem in LTodas do
      if LOrdem.Status in AStatus then
        LLista.Add(LOrdem);
    Result := LLista.ToArray;
  finally
    LLista.Free;
  end;
end;

function TRepositorioOrdensFB.DoProduto(
  AProdutoId: Integer): TArray<TOrdemProducao>;
begin
  Result := CarregarPorSql(' WHERE PRODUTOID = :P ORDER BY ID', [AProdutoId]);
end;

function TRepositorioOrdensFB.ProximoNumero: string;
begin
  Result := Format('OP-%.5d', [Contar + 1]);
end;

end.
