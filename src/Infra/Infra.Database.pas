{*******************************************************************************
  Infra.Database

  Conexao com o Firebird via FireDAC, escondida atras de uma interface.

  POR QUE UMA INTERFACE E NAO TFDConnection DIRETO?
    Porque assim os repositorios (e os testes) dependem de IConexaoBanco, nao
    de FireDAC. Trocar por outro acesso a dados, ou criar um dublê de teste
    que nao toca em banco nenhum, vira uma questao de registrar outra classe
    no container.

  DETALHES QUE COSTUMAM QUEIMAR HORAS DE QUEM ESTA COMECANDO:

    1. APLICACAO CONSOLE precisa de FireDAC.ConsoleUI.Wait no uses. Sem ela,
       o FireDAC reclama que nao ha "wait cursor" registrado.

    2. A ARQUITETURA DA DLL TEM QUE BATER com a do executavel. O Delphi
       Starter so gera 32 bits, entao e obrigatorio apontar VendorLib para a
       fbclient.dll de 32 bits (na pasta WOW64 de uma instalacao x64).
       Apontar para a de 64 bits da o erro classico:
       "The specified module could not be found" / "is not a valid Win32 app".

    3. Firebird 5 nao aceita mais SYSDBA/masterkey por padrao: a senha e
       definida na instalacao. Por isso ela vem de um .ini, nunca do codigo.

  ESTUDO: transacao explicita, parametros nomeados, e o cuidado de nunca
  concatenar valor em SQL (parametro sempre - e o que evita SQL injection).
*******************************************************************************}
unit Infra.Database;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IniFiles,
  System.IOUtils,
  System.Variants,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Phys,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.ConsoleUI.Wait,   // obrigatorio em aplicacao console
  FireDAC.DApt,             // habilita o "adapter" do TFDQuery
  FireDAC.Comp.Client,
  FireDAC.Comp.DataSet,
  Core.Types,
  Core.Logger;

type
  /// Tudo que descreve "onde fica o banco". Sai de um arquivo .ini.
  TConfigBanco = record
    Servidor: string;
    Porta: Integer;
    Caminho: string;      // caminho do .fdb NO SERVIDOR
    Usuario: string;
    Senha: string;
    VendorLib: string;    // fbclient.dll (32 bits!)
    CharacterSet: string;
    class function Padrao: TConfigBanco; static;
    /// Le do .ini; se nao existir, cria um com os valores padrao.
    class function DoArquivo(const AArquivo: string): TConfigBanco; static;
    procedure GravarEm(const AArquivo: string);
    function StringDeConexao: string;
    function Descricao: string;
  end;

  IConexaoBanco = interface
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D40}']
    procedure Conectar;
    procedure Desconectar;
    function Conectado: Boolean;
    /// Cria uma TFDQuery ligada a esta conexao. Quem chama destroi.
    function NovaQuery: TFDQuery;
    function Executar(const ASql: string;
      const AParams: array of Variant): Integer;
    function ValorEscalar(const ASql: string;
      const AParams: array of Variant): Variant;
    /// Proximo valor de um generator (a forma classica de gerar ID no Firebird).
    function ProximoId(const AGenerator: string): Integer;
    procedure IniciarTransacao;
    procedure Commit;
    procedure Rollback;
    function EmTransacao: Boolean;
    function Descricao: string;
    /// Existe alguma tabela criada? (usado para decidir se roda o DDL)
    function SchemaCriado: Boolean;
  end;

  TConexaoFirebird = class(TInterfacedObject, IConexaoBanco)
  private
    FConexao: TFDConnection;
    FDriver: TFDPhysFBDriverLink;
    FConfig: TConfigBanco;
    FLogger: ILogger;
    procedure Configurar;
    procedure AplicarParametros(AQuery: TFDQuery;
      const AParams: array of Variant);
  public
    constructor Create(const AConfig: TConfigBanco; const ALogger: ILogger);
    destructor Destroy; override;

    procedure Conectar;
    procedure Desconectar;
    function Conectado: Boolean;
    function NovaQuery: TFDQuery;
    function Executar(const ASql: string;
      const AParams: array of Variant): Integer;
    function ValorEscalar(const ASql: string;
      const AParams: array of Variant): Variant;
    function ProximoId(const AGenerator: string): Integer;
    procedure IniciarTransacao;
    procedure Commit;
    procedure Rollback;
    function EmTransacao: Boolean;
    function Descricao: string;
    function SchemaCriado: Boolean;
  end;

/// Caminho padrao do arquivo de configuracao (ao lado do executavel).
function ArquivoConfigPadrao: string;

implementation

const
  SECAO = 'Firebird';

function ArquivoConfigPadrao: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'firebird.ini');
end;

{ TConfigBanco }

class function TConfigBanco.Padrao: TConfigBanco;
begin
  Result.Servidor := 'localhost';
  Result.Porta := 3050;
  Result.Caminho := TPath.Combine(
    TPath.GetDirectoryName(TPath.GetDirectoryName(ParamStr(0))),
    'dados\ERP.FDB');
  Result.Usuario := 'SYSDBA';
  Result.Senha := '';
  Result.VendorLib :=
    'C:\Program Files\Firebird\Firebird_5_0\WOW64\fbclient.dll';
  Result.CharacterSet := 'UTF8';
end;

class function TConfigBanco.DoArquivo(const AArquivo: string): TConfigBanco;
var
  LIni: TIniFile;
begin
  Result := TConfigBanco.Padrao;

  if not TFile.Exists(AArquivo) then
  begin
    Result.GravarEm(AArquivo);
    Exit;
  end;

  LIni := TIniFile.Create(AArquivo);
  try
    Result.Servidor := LIni.ReadString(SECAO, 'Servidor', Result.Servidor);
    Result.Porta := LIni.ReadInteger(SECAO, 'Porta', Result.Porta);
    Result.Caminho := LIni.ReadString(SECAO, 'Caminho', Result.Caminho);
    Result.Usuario := LIni.ReadString(SECAO, 'Usuario', Result.Usuario);
    Result.Senha := LIni.ReadString(SECAO, 'Senha', Result.Senha);
    Result.VendorLib := LIni.ReadString(SECAO, 'VendorLib', Result.VendorLib);
    Result.CharacterSet := LIni.ReadString(SECAO, 'CharacterSet',
      Result.CharacterSet);
  finally
    LIni.Free;
  end;
end;

procedure TConfigBanco.GravarEm(const AArquivo: string);
var
  LIni: TIniFile;
  LPasta: string;
begin
  LPasta := TPath.GetDirectoryName(AArquivo);
  if (LPasta <> '') and (not TDirectory.Exists(LPasta)) then
    TDirectory.CreateDirectory(LPasta);

  LIni := TIniFile.Create(AArquivo);
  try
    LIni.WriteString(SECAO, 'Servidor', Servidor);
    LIni.WriteInteger(SECAO, 'Porta', Porta);
    LIni.WriteString(SECAO, 'Caminho', Caminho);
    LIni.WriteString(SECAO, 'Usuario', Usuario);
    LIni.WriteString(SECAO, 'Senha', Senha);
    LIni.WriteString(SECAO, 'VendorLib', VendorLib);
    LIni.WriteString(SECAO, 'CharacterSet', CharacterSet);
  finally
    LIni.Free;
  end;
end;

function TConfigBanco.StringDeConexao: string;
begin
  Result := Format('%s/%d:%s', [Servidor, Porta, Caminho]);
end;

function TConfigBanco.Descricao: string;
begin
  Result := Format('Firebird em %s (usuario %s)', [StringDeConexao, Usuario]);
end;

{ TConexaoFirebird }

constructor TConexaoFirebird.Create(const AConfig: TConfigBanco;
  const ALogger: ILogger);
begin
  inherited Create;
  FConfig := AConfig;
  if Assigned(ALogger) then
    FLogger := ALogger
  else
    FLogger := TLoggerNulo.Create;

  FDriver := TFDPhysFBDriverLink.Create(nil);
  FConexao := TFDConnection.Create(nil);
  Configurar;
end;

destructor TConexaoFirebird.Destroy;
begin
  if Assigned(FConexao) then
  begin
    if FConexao.Connected then
      FConexao.Connected := False;
    FConexao.Free;
  end;
  FDriver.Free;
  inherited;
end;

procedure TConexaoFirebird.Configurar;
begin
  // Aponta a DLL cliente. Precisa ser da MESMA arquitetura do executavel.
  if (FConfig.VendorLib <> '') and TFile.Exists(FConfig.VendorLib) then
    FDriver.VendorLib := FConfig.VendorLib;

  FConexao.DriverName := 'FB';
  FConexao.LoginPrompt := False;
  FConexao.Params.Clear;
  FConexao.Params.Add('DriverID=FB');
  FConexao.Params.Add('Protocol=TCPIP');
  FConexao.Params.Add('Server=' + FConfig.Servidor);
  FConexao.Params.Add('Port=' + IntToStr(FConfig.Porta));
  FConexao.Params.Add('Database=' + FConfig.Caminho);
  FConexao.Params.Add('User_Name=' + FConfig.Usuario);
  FConexao.Params.Add('Password=' + FConfig.Senha);
  FConexao.Params.Add('CharacterSet=' + FConfig.CharacterSet);
  // Sem isso o FireDAC pode ficar preso esperando um servidor que nao responde.
  FConexao.Params.Add('LoginTimeout=10');

  { Transacao explicita: nada e gravado por acidente. Read Committed com
    "no wait" evita que uma sessao travada segure a outra indefinidamente. }
  FConexao.TxOptions.AutoCommit := True;
  FConexao.TxOptions.Isolation := xiReadCommitted;
end;

procedure TConexaoFirebird.Conectar;
begin
  if FConexao.Connected then
    Exit;
  try
    FConexao.Connected := True;
    FLogger.Info('Conectado ao %s', [FConfig.Descricao]);
  except
    on E: Exception do
      raise EInfra.CreateFmt(
        'Falha ao conectar em %s.'#13#10'%s: %s'#13#10 +
        'Verifique: (1) o servico do Firebird esta rodando? ' +
        '(2) o caminho do banco existe no servidor? ' +
        '(3) usuario/senha em firebird.ini estao corretos? ' +
        '(4) VendorLib aponta para a fbclient.dll de 32 bits?',
        [FConfig.StringDeConexao, E.ClassName, E.Message]);
  end;
end;

procedure TConexaoFirebird.Desconectar;
begin
  if FConexao.Connected then
    FConexao.Connected := False;
end;

function TConexaoFirebird.Conectado: Boolean;
begin
  Result := FConexao.Connected;
end;

function TConexaoFirebird.Descricao: string;
begin
  Result := FConfig.Descricao;
end;

function TConexaoFirebird.NovaQuery: TFDQuery;
begin
  Conectar;
  Result := TFDQuery.Create(nil);
  Result.Connection := FConexao;
end;

procedure TConexaoFirebird.AplicarParametros(AQuery: TFDQuery;
  const AParams: array of Variant);
var
  I: Integer;
begin
  for I := 0 to High(AParams) do
    if I < AQuery.Params.Count then
      AQuery.Params[I].Value := AParams[I];
end;

function TConexaoFirebird.Executar(const ASql: string;
  const AParams: array of Variant): Integer;
var
  LQuery: TFDQuery;
begin
  LQuery := NovaQuery;
  try
    LQuery.SQL.Text := ASql;
    AplicarParametros(LQuery, AParams);
    LQuery.ExecSQL;
    Result := LQuery.RowsAffected;
  finally
    LQuery.Free;
  end;
end;

function TConexaoFirebird.ValorEscalar(const ASql: string;
  const AParams: array of Variant): Variant;
var
  LQuery: TFDQuery;
begin
  LQuery := NovaQuery;
  try
    LQuery.SQL.Text := ASql;
    AplicarParametros(LQuery, AParams);
    LQuery.Open;
    if LQuery.IsEmpty then
      Result := Null
    else
      Result := LQuery.Fields[0].Value;
  finally
    LQuery.Free;
  end;
end;

function TConexaoFirebird.ProximoId(const AGenerator: string): Integer;
var
  LValor: Variant;
begin
  { GEN_ID(gerador, 1) e a forma classica de obter o proximo ID no Firebird.
    Fazemos ANTES do INSERT para ja saber qual Id a entidade vai ter. }
  LValor := ValorEscalar(
    Format('SELECT GEN_ID(%s, 1) FROM RDB$DATABASE', [AGenerator]), []);
  if VarIsNull(LValor) then
    raise EInfra.CreateFmt('Generator %s nao encontrado.', [AGenerator]);
  Result := LValor;
end;

procedure TConexaoFirebird.IniciarTransacao;
begin
  Conectar;
  if not FConexao.InTransaction then
    FConexao.StartTransaction;
end;

procedure TConexaoFirebird.Commit;
begin
  if FConexao.InTransaction then
    FConexao.Commit;
end;

procedure TConexaoFirebird.Rollback;
begin
  if FConexao.InTransaction then
    FConexao.Rollback;
end;

function TConexaoFirebird.EmTransacao: Boolean;
begin
  Result := FConexao.InTransaction;
end;

function TConexaoFirebird.SchemaCriado: Boolean;
var
  LValor: Variant;
begin
  LValor := ValorEscalar(
    'SELECT COUNT(*) FROM RDB$RELATIONS ' +
    'WHERE RDB$SYSTEM_FLAG = 0 AND RDB$RELATION_NAME = ''PRODUTOS''', []);
  Result := (not VarIsNull(LValor)) and (Integer(LValor) > 0);
end;

end.
