{*******************************************************************************
  Infra.UnitOfWork

  Transacao logica por COMPENSACAO.

  Bancos de dados tem BEGIN/COMMIT/ROLLBACK. Um repositorio em memoria nao tem.
  Entao cada operacao que muda estado registra "como me desfazer" (padrao
  COMMAND); no rollback executamos essas acoes na ordem INVERSA.

  ESTUDO:
    * Padrao Command aplicado a undo
    * Metodos anonimos guardados em lista (TProc)
    * Transacoes ANINHADAS por contagem de nivel: so o Commit mais externo
      confirma de verdade
    * Executar(): elimina a repeticao de try/except/rollback em todo servico
*******************************************************************************}
unit Infra.UnitOfWork;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Core.Types,
  Core.Logger,
  Domain.Interfaces,
  Infra.Database;

type
  TUnitOfWork = class(TInterfacedObject, IUnitOfWork)
  private type
    TCompensacao = record
      Desfazer: TProc;
      Descricao: string;
    end;
  private
    FAcoes: TList<TCompensacao>;
    FNivel: Integer;
    FLogger: ILogger;
  public
    constructor Create(const ALogger: ILogger);
    destructor Destroy; override;

    // virtuais: a versao com banco (abaixo) precisa acrescentar
    // BEGIN/COMMIT/ROLLBACK de verdade sem reescrever a compensacao.
    procedure Iniciar; virtual;
    procedure Commit; virtual;
    procedure Rollback; virtual;
    function EmTransacao: Boolean;
    procedure RegistrarDesfazer(const ADesfazer: TProc;
      const ADescricao: string = '');
    function OperacoesPendentes: Integer;
    procedure Executar(const ABloco: TProc);
  end;

  { --------------------------------------------------------------------------
    UNIT OF WORK COM BANCO

    Com Firebird no lugar da memoria, um rollback precisa desfazer DUAS coisas:

      1. o que foi gravado no banco   -> ROLLBACK da transacao
      2. o estado dos OBJETOS vivos   -> as acoes de compensacao

    O item 2 e facil de esquecer: o mapa de identidade (ver
    Infra.Repositories.Firebird) mantem os objetos em memoria, e um rollback
    no banco NAO desfaz o "Produto.Estoque := 5" que ja aconteceu em RAM.
    Sem os dois, o sistema fica mentindo para si mesmo.
    -------------------------------------------------------------------------- }
  TUnitOfWorkFirebird = class(TUnitOfWork)
  private
    FConexao: IConexaoBanco;
  public
    constructor Create(const AConexao: IConexaoBanco; const ALogger: ILogger);
      reintroduce;
    procedure Iniciar; override;
    procedure Commit; override;
    procedure Rollback; override;
  end;

implementation

{ TUnitOfWork }

constructor TUnitOfWork.Create(const ALogger: ILogger);
begin
  inherited Create;
  FAcoes := TList<TCompensacao>.Create;
  if Assigned(ALogger) then
    FLogger := ALogger
  else
    FLogger := TLoggerNulo.Create;
end;

destructor TUnitOfWork.Destroy;
begin
  FAcoes.Free;
  inherited;
end;

procedure TUnitOfWork.Iniciar;
begin
  Inc(FNivel);
  if FNivel = 1 then
  begin
    FAcoes.Clear;
    FLogger.Debug('UoW: transacao iniciada.');
  end
  else
    FLogger.Debug('UoW: transacao aninhada (nivel %d).', [FNivel]);
end;

procedure TUnitOfWork.Commit;
begin
  if FNivel = 0 then
    raise EInfra.Create('Commit sem transacao ativa.');

  Dec(FNivel);
  if FNivel = 0 then
  begin
    FLogger.Debug('UoW: commit de %d operacao(oes).', [FAcoes.Count]);
    FAcoes.Clear; // confirmado: as compensacoes nao sao mais necessarias
  end;
end;

procedure TUnitOfWork.Rollback;
var
  I: Integer;
  LAcao: TCompensacao;
begin
  if FNivel = 0 then
    Exit;

  FLogger.Aviso('UoW: rollback de %d operacao(oes).', [FAcoes.Count]);

  // Ordem inversa: a ultima coisa feita e a primeira a ser desfeita.
  for I := FAcoes.Count - 1 downto 0 do
  begin
    LAcao := FAcoes[I];
    try
      if Assigned(LAcao.Desfazer) then
        LAcao.Desfazer();
    except
      on E: Exception do
        // Um rollback que falha nao pode interromper os demais.
        FLogger.Erro('UoW: falha ao desfazer "%s": %s',
          [LAcao.Descricao, E.Message]);
    end;
  end;

  FAcoes.Clear;
  FNivel := 0;
end;

function TUnitOfWork.EmTransacao: Boolean;
begin
  Result := FNivel > 0;
end;

procedure TUnitOfWork.RegistrarDesfazer(const ADesfazer: TProc;
  const ADescricao: string);
var
  LAcao: TCompensacao;
begin
  if not EmTransacao then
    Exit; // fora de transacao a operacao e auto-confirmada

  LAcao.Desfazer := ADesfazer;
  LAcao.Descricao := ADescricao;
  FAcoes.Add(LAcao);
end;

function TUnitOfWork.OperacoesPendentes: Integer;
begin
  Result := FAcoes.Count;
end;

procedure TUnitOfWork.Executar(const ABloco: TProc);
begin
  Iniciar;
  try
    ABloco();
    Commit;
  except
    Rollback;
    raise;  // o chamador decide o que fazer com o erro
  end;
end;

{ TUnitOfWorkFirebird }

constructor TUnitOfWorkFirebird.Create(const AConexao: IConexaoBanco;
  const ALogger: ILogger);
begin
  inherited Create(ALogger);
  if AConexao = nil then
    raise EInfra.Create('Unit of Work com banco exige uma conexao.');
  FConexao := AConexao;
end;

procedure TUnitOfWorkFirebird.Iniciar;
begin
  // So a transacao MAIS EXTERNA abre transacao no banco (o Firebird nao
  // tem transacao aninhada aqui; o controle de nivel fica no pai).
  if not EmTransacao then
    FConexao.IniciarTransacao;
  inherited;
end;

procedure TUnitOfWorkFirebird.Commit;
begin
  inherited;              // decrementa o nivel e limpa as compensacoes
  if not EmTransacao then
    FConexao.Commit;      // so confirma quando saiu do nivel mais externo
end;

procedure TUnitOfWorkFirebird.Rollback;
begin
  FConexao.Rollback;      // 1) desfaz no banco
  inherited;              // 2) desfaz o estado dos objetos em memoria
end;

end.
