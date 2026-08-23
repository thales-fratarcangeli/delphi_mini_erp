{*******************************************************************************
  Core.Logger

  Sistema de log baseado em interfaces.

  ESTUDO - padroes de projeto demonstrados aqui:
    * Programar para INTERFACE, nao para implementacao (ILogger)
    * Template Method  -> TLoggerBase implementa Info/Erro/... e delega a
                          Escrever(), que cada filho implementa
    * Composite        -> TLoggerComposto escreve em varios loggers de uma vez
    * Decorator        -> TLoggerFiltrado embrulha outro logger e filtra nivel
    * Null Object      -> TLoggerNulo evita "if Assigned(Logger) then..."
    * Gerencia de vida -> TInterfacedObject usa contagem de referencia (ARC):
                          nao chame Free em quem voce guarda como interface!
*******************************************************************************}
unit Core.Logger;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections;

type
  TNivelLog = (nlDebug, nlInfo, nlAviso, nlErro);

  ILogger = interface
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D01}']
    procedure Log(ANivel: TNivelLog; const AMensagem: string);
    procedure Debug(const AMensagem: string); overload;
    procedure Debug(const AMensagem: string; const AArgs: array of const); overload;
    procedure Info(const AMensagem: string); overload;
    procedure Info(const AMensagem: string; const AArgs: array of const); overload;
    procedure Aviso(const AMensagem: string); overload;
    procedure Aviso(const AMensagem: string; const AArgs: array of const); overload;
    procedure Erro(const AMensagem: string); overload;
    procedure Erro(const AMensagem: string; const AArgs: array of const); overload;
    procedure ErroExcecao(E: Exception; const AContexto: string);
  end;

  /// Classe base: implementa toda a comodidade e deixa so Escrever() abstrato.
  TLoggerBase = class abstract(TInterfacedObject, ILogger)
  protected
    function Formatar(ANivel: TNivelLog; const AMensagem: string): string; virtual;
    procedure Escrever(ANivel: TNivelLog; const ALinha: string); virtual; abstract;
  public
    // virtual de proposito: quem implementa ILogger precisa poder trocar o
    // comportamento pela VMT, senao o despacho pela interface chamaria sempre
    // a versao da classe base (metodos estaticos sao ligados na declaracao).
    procedure Log(ANivel: TNivelLog; const AMensagem: string); virtual;
    procedure Debug(const AMensagem: string); overload;
    procedure Debug(const AMensagem: string; const AArgs: array of const); overload;
    procedure Info(const AMensagem: string); overload;
    procedure Info(const AMensagem: string; const AArgs: array of const); overload;
    procedure Aviso(const AMensagem: string); overload;
    procedure Aviso(const AMensagem: string; const AArgs: array of const); overload;
    procedure Erro(const AMensagem: string); overload;
    procedure Erro(const AMensagem: string; const AArgs: array of const); overload;
    procedure ErroExcecao(E: Exception; const AContexto: string);
  end;

  TConsoleLogger = class(TLoggerBase)
  protected
    procedure Escrever(ANivel: TNivelLog; const ALinha: string); override;
  end;

  /// Grava em arquivo. Usa TCriticalSection porque varias threads podem logar.
  TArquivoLogger = class(TLoggerBase)
  private
    FArquivo: string;
    FLock: TCriticalSection;
  protected
    procedure Escrever(ANivel: TNivelLog; const ALinha: string); override;
  public
    constructor Create(const AArquivo: string);
    destructor Destroy; override;
  end;

  /// Guarda as ultimas N linhas em memoria (util para testes e para a tela).
  TMemoriaLogger = class(TLoggerBase)
  private
    FLinhas: TStringList;
    FLimite: Integer;
    FLock: TCriticalSection;
  protected
    procedure Escrever(ANivel: TNivelLog; const ALinha: string); override;
  public
    constructor Create(ALimite: Integer = 500);
    destructor Destroy; override;
    function Linhas: TArray<string>;
    function Contem(const ATrecho: string): Boolean;
    procedure Limpar;
  end;

  /// COMPOSITE: trata varios loggers como se fosse um so.
  TLoggerComposto = class(TLoggerBase)
  private
    FDestinos: TList<ILogger>;
  protected
    procedure Escrever(ANivel: TNivelLog; const ALinha: string); override;
  public
    constructor Create(const ADestinos: array of ILogger);
    destructor Destroy; override;
    procedure Log(ANivel: TNivelLog; const AMensagem: string); override;
  end;

  /// DECORATOR: so deixa passar mensagens a partir de um nivel minimo.
  TLoggerFiltrado = class(TLoggerBase)
  private
    FInterno: ILogger;
    FNivelMinimo: TNivelLog;
  protected
    procedure Escrever(ANivel: TNivelLog; const ALinha: string); override;
  public
    constructor Create(const AInterno: ILogger; ANivelMinimo: TNivelLog);
    procedure Log(ANivel: TNivelLog; const AMensagem: string); override;
  end;

  /// NULL OBJECT: engole tudo. Evita testes de nil espalhados pelo codigo.
  TLoggerNulo = class(TLoggerBase)
  protected
    procedure Escrever(ANivel: TNivelLog; const ALinha: string); override;
  end;

function NivelLogParaTexto(ANivel: TNivelLog): string;

implementation

uses
  System.IOUtils,
  Core.Types;

function NivelLogParaTexto(ANivel: TNivelLog): string;
begin
  case ANivel of
    nlDebug: Result := 'DEBUG';
    nlInfo:  Result := 'INFO ';
    nlAviso: Result := 'AVISO';
  else
    Result := 'ERRO ';
  end;
end;

{ TLoggerBase }

function TLoggerBase.Formatar(ANivel: TNivelLog; const AMensagem: string): string;
begin
  Result := Format('[%s] [%s] %s',
    [FormatDateTime('hh:nn:ss.zzz', Now), NivelLogParaTexto(ANivel), AMensagem]);
end;

procedure TLoggerBase.Log(ANivel: TNivelLog; const AMensagem: string);
begin
  Escrever(ANivel, Formatar(ANivel, AMensagem));
end;

procedure TLoggerBase.Debug(const AMensagem: string);
begin
  Log(nlDebug, AMensagem);
end;

procedure TLoggerBase.Debug(const AMensagem: string; const AArgs: array of const);
begin
  Log(nlDebug, Format(AMensagem, AArgs));
end;

procedure TLoggerBase.Info(const AMensagem: string);
begin
  Log(nlInfo, AMensagem);
end;

procedure TLoggerBase.Info(const AMensagem: string; const AArgs: array of const);
begin
  Log(nlInfo, Format(AMensagem, AArgs));
end;

procedure TLoggerBase.Aviso(const AMensagem: string);
begin
  Log(nlAviso, AMensagem);
end;

procedure TLoggerBase.Aviso(const AMensagem: string; const AArgs: array of const);
begin
  Log(nlAviso, Format(AMensagem, AArgs));
end;

procedure TLoggerBase.Erro(const AMensagem: string);
begin
  Log(nlErro, AMensagem);
end;

procedure TLoggerBase.Erro(const AMensagem: string; const AArgs: array of const);
begin
  Log(nlErro, Format(AMensagem, AArgs));
end;

procedure TLoggerBase.ErroExcecao(E: Exception; const AContexto: string);
begin
  Log(nlErro, Format('%s -> %s: %s', [AContexto, E.ClassName, E.Message]));
end;

{ TConsoleLogger }

procedure TConsoleLogger.Escrever(ANivel: TNivelLog; const ALinha: string);
begin
  if IsConsole then
    Writeln(ALinha);
end;

{ TArquivoLogger }

constructor TArquivoLogger.Create(const AArquivo: string);
var
  LPasta: string;
begin
  inherited Create;
  FArquivo := AArquivo;
  FLock := TCriticalSection.Create;
  LPasta := TPath.GetDirectoryName(AArquivo);
  if (LPasta <> '') and (not TDirectory.Exists(LPasta)) then
    TDirectory.CreateDirectory(LPasta);
end;

destructor TArquivoLogger.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TArquivoLogger.Escrever(ANivel: TNivelLog; const ALinha: string);
var
  LArquivo: TextFile;
begin
  FLock.Enter;
  try
    AssignFile(LArquivo, FArquivo);
    try
      if TFile.Exists(FArquivo) then
        Append(LArquivo)
      else
        Rewrite(LArquivo);
      Writeln(LArquivo, ALinha);
    finally
      CloseFile(LArquivo);
    end;
  except
    // Log nunca pode derrubar a aplicacao: falha de log e engolida de proposito.
  end;
  FLock.Leave;
end;

{ TMemoriaLogger }

constructor TMemoriaLogger.Create(ALimite: Integer);
begin
  inherited Create;
  FLinhas := TStringList.Create;
  FLimite := ALimite;
  FLock := TCriticalSection.Create;
end;

destructor TMemoriaLogger.Destroy;
begin
  FLinhas.Free;
  FLock.Free;
  inherited;
end;

procedure TMemoriaLogger.Escrever(ANivel: TNivelLog; const ALinha: string);
begin
  FLock.Enter;
  try
    FLinhas.Add(ALinha);
    while FLinhas.Count > FLimite do
      FLinhas.Delete(0);
  finally
    FLock.Leave;
  end;
end;

function TMemoriaLogger.Linhas: TArray<string>;
begin
  FLock.Enter;
  try
    Result := FLinhas.ToStringArray;
  finally
    FLock.Leave;
  end;
end;

function TMemoriaLogger.Contem(const ATrecho: string): Boolean;
var
  LLinha: string;
begin
  for LLinha in Linhas do
    if LLinha.Contains(ATrecho) then
      Exit(True);
  Result := False;
end;

procedure TMemoriaLogger.Limpar;
begin
  FLock.Enter;
  try
    FLinhas.Clear;
  finally
    FLock.Leave;
  end;
end;

{ TLoggerComposto }

constructor TLoggerComposto.Create(const ADestinos: array of ILogger);
var
  LDestino: ILogger;
begin
  inherited Create;
  FDestinos := TList<ILogger>.Create;
  for LDestino in ADestinos do
    FDestinos.Add(LDestino);
end;

destructor TLoggerComposto.Destroy;
begin
  FDestinos.Free;
  inherited;
end;

procedure TLoggerComposto.Escrever(ANivel: TNivelLog; const ALinha: string);
begin
  // nao usado: sobrescrevemos Log diretamente para preservar a formatacao
  // de cada destino.
end;

procedure TLoggerComposto.Log(ANivel: TNivelLog; const AMensagem: string);
var
  LDestino: ILogger;
begin
  for LDestino in FDestinos do
    LDestino.Log(ANivel, AMensagem);
end;

{ TLoggerFiltrado }

constructor TLoggerFiltrado.Create(const AInterno: ILogger; ANivelMinimo: TNivelLog);
begin
  inherited Create;
  FInterno := AInterno;
  FNivelMinimo := ANivelMinimo;
end;

procedure TLoggerFiltrado.Escrever(ANivel: TNivelLog; const ALinha: string);
begin
  // idem TLoggerComposto
end;

procedure TLoggerFiltrado.Log(ANivel: TNivelLog; const AMensagem: string);
begin
  if ANivel >= FNivelMinimo then
    FInterno.Log(ANivel, AMensagem);
end;

{ TLoggerNulo }

procedure TLoggerNulo.Escrever(ANivel: TNivelLog; const ALinha: string);
begin
  // proposital: nao faz nada
end;

end.
