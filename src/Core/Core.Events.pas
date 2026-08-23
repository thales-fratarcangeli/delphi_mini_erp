{*******************************************************************************
  Core.Events

  Barramento de eventos em memoria (padroes Observer + Mediator).

  ESTUDO - conceitos demonstrados aqui:
    * Desacoplamento: quem publica nao conhece quem escuta
    * Metodos anonimos (TProc<T>) como handlers
    * Class references (TClass) + ClassParent para despachar tambem para
      assinantes de classes ANCESTRAIS do evento
    * RTTI para transformar o parametro generico T em uma TClass
    * Isolamento de falhas: um assinante que estoura nao derruba os demais

  Uso:
      TEventos.Assinar<TPedidoConfirmado>(Bus,
        procedure(E: TPedidoConfirmado)
        begin
          Writeln('Pedido ', E.PedidoId, ' confirmado');
        end);

      Bus.Publicar(TPedidoConfirmado.Create(10, 1, 250));  // bus assume a posse
*******************************************************************************}
unit Core.Events;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.Generics.Collections,
  Core.Logger;

type
  /// Raiz de todos os eventos de dominio.
  TEventoDominio = class abstract
  private
    FOcorridoEm: TDateTime;
  public
    constructor Create;
    function Descricao: string; virtual;
    property OcorridoEm: TDateTime read FOcorridoEm;
  end;

  TEventoClass = class of TEventoDominio;

  IEventBus = interface
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D03}']
    procedure AssinarClasse(AClasse: TEventoClass; const ANome: string;
      const AHandler: TProc<TEventoDominio>);
    /// O barramento assume a POSSE do evento e o destroi ao final.
    procedure Publicar(AEvento: TEventoDominio);
    function TotalPublicados: Integer;
    function TotalAssinantes: Integer;
    procedure LimparAssinantes;
  end;

  TEventBus = class(TInterfacedObject, IEventBus)
  private type
    TAssinatura = record
      Nome: string;
      Handler: TProc<TEventoDominio>;
    end;
  private
    FAssinaturas: TObjectDictionary<string, TList<TAssinatura>>;
    FLogger: ILogger;
    FTotalPublicados: Integer;
    procedure DespacharPara(AClasse: TClass; AEvento: TEventoDominio);
  public
    constructor Create(const ALogger: ILogger);
    destructor Destroy; override;

    procedure AssinarClasse(AClasse: TEventoClass; const ANome: string;
      const AHandler: TProc<TEventoDominio>);
    procedure Publicar(AEvento: TEventoDominio);
    function TotalPublicados: Integer;
    function TotalAssinantes: Integer;
    procedure LimparAssinantes;
  end;

  /// Fachada generica (interfaces nao suportam metodos genericos).
  TEventos = class
  public
    class procedure Assinar<T: TEventoDominio>(const ABus: IEventBus;
      const AHandler: TProc<T>; const ANome: string = ''); static;
  end;

implementation

uses
  Core.Types;

{ TEventoDominio }

constructor TEventoDominio.Create;
begin
  inherited Create;
  FOcorridoEm := Now;
end;

function TEventoDominio.Descricao: string;
begin
  Result := ClassName;
end;

{ TEventBus }

constructor TEventBus.Create(const ALogger: ILogger);
begin
  inherited Create;
  FAssinaturas := TObjectDictionary<string, TList<TAssinatura>>.Create([doOwnsValues]);
  if Assigned(ALogger) then
    FLogger := ALogger
  else
    FLogger := TLoggerNulo.Create;
end;

destructor TEventBus.Destroy;
begin
  FAssinaturas.Free;
  inherited;
end;

procedure TEventBus.AssinarClasse(AClasse: TEventoClass; const ANome: string;
  const AHandler: TProc<TEventoDominio>);
var
  LLista: TList<TAssinatura>;
  LAssinatura: TAssinatura;
begin
  if AClasse = nil then
    raise EDominio.Create('Classe de evento nao informada.');
  if not Assigned(AHandler) then
    raise EDominio.Create('Handler de evento nao informado.');

  if not FAssinaturas.TryGetValue(AClasse.ClassName, LLista) then
  begin
    LLista := TList<TAssinatura>.Create;
    FAssinaturas.Add(AClasse.ClassName, LLista);
  end;

  LAssinatura.Nome := ANome;
  if LAssinatura.Nome = '' then
    LAssinatura.Nome := Format('handler#%d', [LLista.Count + 1]);
  LAssinatura.Handler := AHandler;
  LLista.Add(LAssinatura);
end;

procedure TEventBus.DespacharPara(AClasse: TClass; AEvento: TEventoDominio);
var
  LLista: TList<TAssinatura>;
  LAssinatura: TAssinatura;
begin
  if not FAssinaturas.TryGetValue(AClasse.ClassName, LLista) then
    Exit;

  for LAssinatura in LLista.ToArray do  // ToArray: handler pode assinar outro
  try
    LAssinatura.Handler(AEvento);
  except
    on E: Exception do
      // Um assinante quebrado NAO pode impedir os outros de rodar.
      FLogger.Erro('Assinante "%s" falhou ao tratar %s: %s',
        [LAssinatura.Nome, AEvento.ClassName, E.Message]);
  end;
end;

procedure TEventBus.Publicar(AEvento: TEventoDominio);
var
  LClasse: TClass;
begin
  if AEvento = nil then
    Exit;
  try
    Inc(FTotalPublicados);
    FLogger.Debug('Evento publicado: %s', [AEvento.Descricao]);

    // Sobe a hierarquia: quem assina TEventoDominio recebe TUDO.
    LClasse := AEvento.ClassType;
    while (LClasse <> nil) and LClasse.InheritsFrom(TEventoDominio) do
    begin
      DespacharPara(LClasse, AEvento);
      LClasse := LClasse.ClassParent;
    end;
  finally
    AEvento.Free; // o barramento e o dono do evento
  end;
end;

function TEventBus.TotalPublicados: Integer;
begin
  Result := FTotalPublicados;
end;

function TEventBus.TotalAssinantes: Integer;
var
  LLista: TList<TAssinatura>;
begin
  Result := 0;
  for LLista in FAssinaturas.Values do
    Inc(Result, LLista.Count);
end;

procedure TEventBus.LimparAssinantes;
begin
  FAssinaturas.Clear;
end;

{ TEventos }

class procedure TEventos.Assinar<T>(const ABus: IEventBus;
  const AHandler: TProc<T>; const ANome: string);
var
  LCtx: TRttiContext;
  LTipo: TRttiInstanceType;
begin
  LCtx := TRttiContext.Create;
  try
    // De um parametro generico T so conseguimos chegar na TClass via RTTI.
    LTipo := LCtx.GetType(TypeInfo(T)) as TRttiInstanceType;
    ABus.AssinarClasse(TEventoClass(LTipo.MetaclassType), ANome,
      procedure(AEvento: TEventoDominio)
      begin
        AHandler(T(AEvento)); // seguro: o bus so chama para a classe certa
      end);
  finally
    LCtx.Free;
  end;
end;

end.
