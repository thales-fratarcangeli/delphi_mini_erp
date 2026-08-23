{*******************************************************************************
  Core.Container

  Container de Injecao de Dependencia (IoC) escrito do zero.

  ESTUDO - conceitos demonstrados aqui:
    * Inversao de Controle: quem usa nao instancia, apenas pede
    * Metodos genericos + TypeInfo/GetTypeData para descobrir o GUID da interface
    * Supports() como forma segura de fazer "cast" entre interfaces
    * Escopo Singleton x Transiente (uma instancia so x uma nova a cada pedido)
    * Deteccao de dependencia circular (pilha de resolucao)
    * Limitacao da linguagem: INTERFACES NAO PODEM TER METODOS GENERICOS,
      por isso a classe auxiliar TDI existe.

  Uso tipico:
      TDI.Registrar<ILogger>(Container,
        function(const C: IContainer): IInterface
        begin
          Result := TConsoleLogger.Create;
        end);
      ...
      Log := TDI.Resolver<ILogger>(Container);
*******************************************************************************}
unit Core.Container;

interface

uses
  System.SysUtils,
  System.TypInfo,
  System.Classes,
  System.Generics.Collections,
  Core.Types;

type
  TEscopo = (esSingleton, esTransiente);

  IContainer = interface;

  { ARMADILHA CLASSICA DE ARC (e por que a fabrica RECEBE o container):

    Se a fabrica fosse um TFunc<IInterface> que CAPTURASSE o container,
    cada closure guardaria uma referencia forte a ele -- e o container guarda
    as closures. Resultado: ciclo de referencia, contador nunca chega a zero,
    e NADA e destruido (nem os servicos que ele criou).

    Recebendo o container por parametro, a closure nao captura nada e o ciclo
    desaparece. Rode "GestaoComercial.exe --vazamentos" e veja por si. }
  TFabricaServico = reference to function(const AContainer: IContainer): IInterface;

  IContainer = interface
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D02}']
    procedure RegistrarChave(const AChave: string;
      const AFabrica: TFabricaServico; AEscopo: TEscopo);
    function ResolverChave(const AChave: string): IInterface;
    function EstaRegistrado(const AChave: string): Boolean;
    function Registros: TArray<string>;
    procedure Limpar;
  end;

  TContainer = class(TInterfacedObject, IContainer)
  private type
    TRegistro = record
      Fabrica: TFabricaServico;
      Escopo: TEscopo;
    end;
  private
    FRegistros: TDictionary<string, TRegistro>;
    FSingletons: TDictionary<string, IInterface>;
    FResolvendo: TStack<string>;
    procedure ChecarCiclo(const AChave: string);
  public
    constructor Create;
    destructor Destroy; override;

    procedure RegistrarChave(const AChave: string;
      const AFabrica: TFabricaServico; AEscopo: TEscopo);
    function ResolverChave(const AChave: string): IInterface;
    function EstaRegistrado(const AChave: string): Boolean;
    function Registros: TArray<string>;
    procedure Limpar;
  end;

  { Fachada generica sobre IContainer.
    Interfaces nao aceitam metodos genericos em Delphi -> usamos class methods. }
  TDI = class
  public
    class function Chave<T>: string; static;

    class procedure Registrar<T: IInterface>(const AContainer: IContainer;
      const AFabrica: TFabricaServico;
      AEscopo: TEscopo = esSingleton); static;

    /// Registra uma instancia ja criada (util em testes: injeta um fake)
    class procedure RegistrarInstancia<T: IInterface>(const AContainer: IContainer;
      const AInstancia: IInterface); static;

    class function Resolver<T: IInterface>(const AContainer: IContainer): T; static;

    class function TentarResolver<T: IInterface>(const AContainer: IContainer;
      out AServico: T): Boolean; static;
  end;

implementation

{ TContainer }

constructor TContainer.Create;
begin
  inherited Create;
  FRegistros := TDictionary<string, TRegistro>.Create;
  FSingletons := TDictionary<string, IInterface>.Create;
  FResolvendo := TStack<string>.Create;
end;

destructor TContainer.Destroy;
begin
  FResolvendo.Free;
  FSingletons.Free;   // libera as referencias -> ARC destroi os objetos
  FRegistros.Free;
  inherited;
end;

procedure TContainer.RegistrarChave(const AChave: string;
  const AFabrica: TFabricaServico; AEscopo: TEscopo);
var
  LRegistro: TRegistro;
begin
  if not Assigned(AFabrica) then
    raise EConfiguracao.CreateFmt('Fabrica nula ao registrar "%s".', [AChave]);
  LRegistro.Fabrica := AFabrica;
  LRegistro.Escopo := AEscopo;
  FRegistros.AddOrSetValue(AChave, LRegistro);
  FSingletons.Remove(AChave); // re-registro invalida singleton anterior
end;

procedure TContainer.ChecarCiclo(const AChave: string);
var
  LItem, LPasso: string;
  LCaminho: string;
begin
  for LItem in FResolvendo do
    if SameText(LItem, AChave) then
    begin
      LCaminho := '';
      for LPasso in FResolvendo do
        LCaminho := LPasso + ' -> ' + LCaminho;
      raise EConfiguracao.CreateFmt(
        'Dependencia circular detectada ao resolver "%s". Caminho: %s%s',
        [AChave, LCaminho, AChave]);
    end;
end;

function TContainer.ResolverChave(const AChave: string): IInterface;
var
  LRegistro: TRegistro;
  LInstancia: IInterface;
begin
  if not FRegistros.TryGetValue(AChave, LRegistro) then
    raise EConfiguracao.CreateFmt(
      'Servico "%s" nao registrado no container.', [AChave]);

  if (LRegistro.Escopo = esSingleton) and FSingletons.TryGetValue(AChave, LInstancia) then
    Exit(LInstancia);

  ChecarCiclo(AChave);
  FResolvendo.Push(AChave);
  try
    LInstancia := LRegistro.Fabrica(Self);
  finally
    FResolvendo.Pop;
  end;

  if not Assigned(LInstancia) then
    raise EConfiguracao.CreateFmt('A fabrica de "%s" devolveu nil.', [AChave]);

  if LRegistro.Escopo = esSingleton then
    FSingletons.AddOrSetValue(AChave, LInstancia);

  Result := LInstancia;
end;

function TContainer.EstaRegistrado(const AChave: string): Boolean;
begin
  Result := FRegistros.ContainsKey(AChave);
end;

function TContainer.Registros: TArray<string>;
begin
  Result := FRegistros.Keys.ToArray;
end;

procedure TContainer.Limpar;
begin
  FSingletons.Clear;
  FRegistros.Clear;
end;

{ TDI }

class function TDI.Chave<T>: string;
var
  LInfo: PTypeInfo;
begin
  LInfo := TypeInfo(T);
  if LInfo = nil then
    raise EConfiguracao.Create('Tipo sem RTTI nao pode ser usado no container.');
  Result := string(LInfo^.Name);
end;

class procedure TDI.Registrar<T>(const AContainer: IContainer;
  const AFabrica: TFabricaServico; AEscopo: TEscopo);
begin
  AContainer.RegistrarChave(Chave<T>, AFabrica, AEscopo);
end;

class procedure TDI.RegistrarInstancia<T>(const AContainer: IContainer;
  const AInstancia: IInterface);
begin
  AContainer.RegistrarChave(Chave<T>,
    function(const AAlvo: IContainer): IInterface
    begin
      Result := AInstancia;
    end,
    esSingleton);
end;

class function TDI.Resolver<T>(const AContainer: IContainer): T;
var
  LInfo: PTypeInfo;
  LBruto: IInterface;
begin
  LInfo := TypeInfo(T);
  if LInfo^.Kind <> tkInterface then
    raise EConfiguracao.CreateFmt('%s nao e uma interface.', [string(LInfo^.Name)]);

  LBruto := AContainer.ResolverChave(string(LInfo^.Name));

  // Supports faz QueryInterface usando o GUID declarado na interface.
  // Se a interface nao tiver GUID ['{...}'], isso falha em tempo de execucao.
  if not Supports(LBruto, GetTypeData(LInfo)^.Guid, Result) then
    raise EConfiguracao.CreateFmt(
      'A instancia registrada nao implementa %s (faltou o GUID na interface?).',
      [string(LInfo^.Name)]);
end;

class function TDI.TentarResolver<T>(const AContainer: IContainer;
  out AServico: T): Boolean;
begin
  Result := False;
  AServico := Default(T);
  if not AContainer.EstaRegistrado(Chave<T>) then
    Exit;
  AServico := Resolver<T>(AContainer);
  Result := True;
end;

end.
