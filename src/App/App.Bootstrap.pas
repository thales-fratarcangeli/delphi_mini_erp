{*******************************************************************************
  App.Bootstrap

  A "raiz de composicao" (composition root): o UNICO lugar do sistema que sabe
  qual implementacao concreta atende cada interface.

  ESTUDO:
    * Repare que aqui aparecem TRepositorioMemoria, TGatewaySimulado etc.
      Em nenhum outro ponto do dominio esses nomes concretos sao citados.
      Trocar memoria por banco = mudar SO ESTE ARQUIVO.
    * As fabricas sao PREGUICOSAS (lazy): o objeto so nasce quando alguem pede,
      e as dependencias sao resolvidas em cascata pelo container.
    * Assinaturas de eventos concentradas em um lugar: da para ler todos os
      efeitos colaterais do sistema de uma vez.
*******************************************************************************}
unit App.Bootstrap;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Core.Types,
  Core.Logger,
  Core.Events,
  Core.Container,
  Domain.Entities,
  Domain.Enums,
  Domain.Events,
  Domain.Interfaces,
  Domain.Services,
  Domain.Producao,
  Domain.Producao.Services,
  Infra.Repositories,
  Infra.Repositories.Firebird,
  Infra.Database,
  Infra.Schema,
  Infra.UnitOfWork,
  Infra.Gateway,
  Infra.Persistence;

type
  { ONDE OS DADOS FICAM.

    A troca entre os dois modos acontece SO no registro de servicos abaixo:
    nem o dominio nem a tela sabem qual esta em uso. E o teste pratico de que
    a arquitetura em camadas funcionou. }
  TModoPersistencia = (
    mpMemoria,    // rapido, sem dependencia externa - usado nos testes
    mpFirebird    // cliente/servidor, como um ERP de verdade
  );

  TAplicacao = class
  private
    FContainer: IContainer;
    FLogMemoria: TMemoriaLogger;   // referencia "fraca": quem mantem vivo e FLogger
    FLogger: ILogger;
    FMural: TStringList;
    FModoSilencioso: Boolean;
    FPasta: string;
    FModo: TModoPersistencia;
    FConfigBanco: TConfigBanco;
    procedure RegistrarServicos;
    procedure RegistrarRepositoriosMemoria;
    procedure RegistrarRepositoriosFirebird;
    procedure RegistrarAssinaturas;
  public
    constructor Create(AModoSilencioso: Boolean = False;
      const APasta: string = ''; AModo: TModoPersistencia = mpMemoria;
      const AConfigBanco: string = '');
    destructor Destroy; override;

    // Atalhos para o que o resto da aplicacao precisa.
    function Clientes: IRepositorioClientes;
    function Produtos: IRepositorioProdutos;
    function Pedidos: IRepositorioPedidos;
    function Movimentos: IRepositorioMovimentos;
    function Pagamentos: IRepositorioPagamentos;
    function Vendas: IServicoVendas;
    function Estoque: IServicoEstoque;
    function Eventos: IEventBus;
    function Armazenamento: IArmazenamento;
    function Politica: IPoliticaDesconto;
    function UoW: IUnitOfWork;

    // ---- PCP ----
    function Centros: IRepositorioCentros;
    function Estruturas: IRepositorioEstruturas;
    function Roteiros: IRepositorioRoteiros;
    function Ordens: IRepositorioOrdens;
    function Engenharia: IServicoEngenharia;
    function Producao: IServicoProducao;

    /// So existe no modo Firebird; nil no modo memoria.
    function Banco: IConexaoBanco;
    function UsaBanco: Boolean;

    /// Ultimos eventos de dominio observados (para exibir na tela).
    function Mural: TArray<string>;
    procedure LimparMural;
    function LinhasDeLog: TArray<string>;

    property Container: IContainer read FContainer;
    property Logger: ILogger read FLogger;
    property PastaDados: string read FPasta;
    property Modo: TModoPersistencia read FModo;
    property ConfigBanco: TConfigBanco read FConfigBanco;
  end;

implementation

{ TAplicacao }

constructor TAplicacao.Create(AModoSilencioso: Boolean; const APasta: string;
  AModo: TModoPersistencia; const AConfigBanco: string);
var
  LArquivoConfig: string;
begin
  inherited Create;
  FModoSilencioso := AModoSilencioso;
  FModo := AModo;
  FMural := TStringList.Create;

  if APasta <> '' then
    FPasta := APasta
  else
    FPasta := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'dados');

  if FModo = mpFirebird then
  begin
    LArquivoConfig := AConfigBanco;
    if LArquivoConfig = '' then
      LArquivoConfig := ArquivoConfigPadrao;
    FConfigBanco := TConfigBanco.DoArquivo(LArquivoConfig);
    RegistrarMapeamentos;   // mini-ORM: quem e cada tabela
  end;

  FContainer := TContainer.Create;
  RegistrarServicos;
  FLogger := TDI.Resolver<ILogger>(FContainer);
  RegistrarAssinaturas;
end;

destructor TAplicacao.Destroy;
begin
  // A ordem importa: soltamos as interfaces antes de destruir o container.
  FLogger := nil;
  FContainer := nil;
  FMural.Free;
  inherited;
end;

procedure TAplicacao.RegistrarServicos;
var
  LSilencioso: Boolean;
  LPasta: string;
  LConfig: TConfigBanco;
begin
  LSilencioso := FModoSilencioso;
  LPasta := FPasta;

  { Duas precaucoes contra ciclo de referencia aqui:

    1) As fabricas recebem o container pelo parametro "C" em vez de captura-lo
       (ver o comentario longo em Core.Container).
    2) Usamos FContainer (campo) e NAO uma variavel local: todo metodo anonimo
       aninhado carrega uma referencia ao frame de variaveis locais deste
       metodo. Se o container estivesse numa local, o frame o manteria vivo
       para sempre. O campo pertence a Self, que e um ponteiro comum de objeto
       (sem contagem de referencia) - logo, nao fecha ciclo. }

  // ---------------------------------------------------------------- LOGGER
  TDI.Registrar<ILogger>(FContainer,
    function(const C: IContainer): IInterface
    var
      LObjetoMemoria: TMemoriaLogger;
      LMemoria, LConsole: ILogger;
    begin
      LObjetoMemoria := TMemoriaLogger.Create(1000);
      LMemoria := LObjetoMemoria;   // a partir daqui quem manda e o ARC
      Self.FLogMemoria := LObjetoMemoria;

      if LSilencioso then
        // Em teste/demo silenciosa so guardamos em memoria.
        Result := LMemoria
      else
      begin
        // DECORATOR + COMPOSITE: console (so a partir de Info) + memoria.
        LConsole := TLoggerFiltrado.Create(TConsoleLogger.Create, nlInfo);
        Result := TLoggerComposto.Create([LConsole, LMemoria]);
      end;
    end);

  // ------------------------------------------------------------ INFRA BASE
  TDI.Registrar<IEventBus>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TEventBus.Create(TDI.Resolver<ILogger>(C));
    end);

  // A conexao so existe no modo Firebird.
  if FModo = mpFirebird then
  begin
    LConfig := FConfigBanco;
    TDI.Registrar<IConexaoBanco>(FContainer,
      function(const C: IContainer): IInterface
      begin
        Result := TConexaoFirebird.Create(LConfig, TDI.Resolver<ILogger>(C));
      end);
  end;

  TDI.Registrar<IUnitOfWork>(FContainer,
    function(const C: IContainer): IInterface
    begin
      // Com banco, o Unit of Work tambem controla a transacao de verdade.
      if C.EstaRegistrado(TDI.Chave<IConexaoBanco>) then
        Result := TUnitOfWorkFirebird.Create(TDI.Resolver<IConexaoBanco>(C),
          TDI.Resolver<ILogger>(C))
      else
        Result := TUnitOfWork.Create(TDI.Resolver<ILogger>(C));
    end);

  TDI.Registrar<IGatewayPagamento>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TGatewaySimulado.Create(TDI.Resolver<ILogger>(C), 50000);
    end);

  // ---------------------------------------------------------- REPOSITORIOS
  { UNICO ponto do sistema que decide onde os dados ficam.
    Repare que o dominio recebe as MESMAS interfaces nos dois casos. }
  if FModo = mpFirebird then
    RegistrarRepositoriosFirebird
  else
    RegistrarRepositoriosMemoria;

  // --------------------------------------------------- POLITICA DE DESCONTO
  TDI.Registrar<IPoliticaDesconto>(FContainer,
    function(const C: IContainer): IInterface
    begin
      // Troque a composicao abaixo e TODO o sistema muda de comportamento.
      Result := TPoliticaMelhorDesconto.Create([
        TPoliticaCategoria.Create,
        TPoliticaVolume.Create(20, 0.05),
        TPoliticaValor.Create(5000, 0.07)
      ]);
    end);

  // ---------------------------------------------------------------- SERVICOS
  TDI.Registrar<IServicoEngenharia>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TServicoEngenharia.Create(
        TDI.Resolver<IRepositorioProdutos>(C),
        TDI.Resolver<IRepositorioEstruturas>(C),
        TDI.Resolver<IRepositorioRoteiros>(C),
        TDI.Resolver<IRepositorioCentros>(C),
        TDI.Resolver<ILogger>(C));
    end);

  TDI.Registrar<IServicoProducao>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TServicoProducao.Create(
        TDI.Resolver<IRepositorioOrdens>(C),
        TDI.Resolver<IRepositorioProdutos>(C),
        TDI.Resolver<IRepositorioCentros>(C),
        TDI.Resolver<IServicoEngenharia>(C),
        TDI.Resolver<IServicoEstoque>(C),
        TDI.Resolver<IEventBus>(C),
        TDI.Resolver<ILogger>(C),
        TDI.Resolver<IUnitOfWork>(C));
    end);

  TDI.Registrar<IServicoEstoque>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TServicoEstoque.Create(
        TDI.Resolver<IRepositorioProdutos>(C),
        TDI.Resolver<IRepositorioMovimentos>(C),
        TDI.Resolver<IEventBus>(C),
        TDI.Resolver<ILogger>(C),
        TDI.Resolver<IUnitOfWork>(C));
    end);

  TDI.Registrar<IServicoVendas>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TServicoVendas.Create(
        TDI.Resolver<IRepositorioPedidos>(C),
        TDI.Resolver<IRepositorioClientes>(C),
        TDI.Resolver<IRepositorioProdutos>(C),
        TDI.Resolver<IRepositorioPagamentos>(C),
        TDI.Resolver<IServicoEstoque>(C),
        TDI.Resolver<IPoliticaDesconto>(C),
        TDI.Resolver<IGatewayPagamento>(C),
        TDI.Resolver<IEventBus>(C),
        TDI.Resolver<ILogger>(C),
        TDI.Resolver<IUnitOfWork>(C));
    end);

  // ------------------------------------------------------------ PERSISTENCIA
  TDI.Registrar<IArmazenamento>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TArmazenamentoJson.Create(LPasta,
        TDI.Resolver<IRepositorioClientes>(C),
        TDI.Resolver<IRepositorioProdutos>(C),
        TDI.Resolver<IRepositorioPedidos>(C),
        TDI.Resolver<IRepositorioMovimentos>(C),
        TDI.Resolver<IRepositorioPagamentos>(C),
        TDI.Resolver<ILogger>(C));
    end);
end;

procedure TAplicacao.RegistrarRepositoriosMemoria;
begin
  TDI.Registrar<IRepositorioClientes>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioClientes.Create;
    end);
  TDI.Registrar<IRepositorioProdutos>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioProdutos.Create;
    end);
  TDI.Registrar<IRepositorioPedidos>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioPedidos.Create;
    end);
  TDI.Registrar<IRepositorioMovimentos>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioMovimentos.Create;
    end);
  TDI.Registrar<IRepositorioPagamentos>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioPagamentos.Create;
    end);
  TDI.Registrar<IRepositorioCentros>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioCentros.Create;
    end);
  TDI.Registrar<IRepositorioEstruturas>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioEstruturas.Create;
    end);
  TDI.Registrar<IRepositorioRoteiros>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioRoteiros.Create;
    end);
  TDI.Registrar<IRepositorioOrdens>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioOrdens.Create;
    end);
end;

procedure TAplicacao.RegistrarRepositoriosFirebird;
begin
  { Mesmas chaves, implementacoes diferentes. Nenhum servico de dominio
    percebe a troca - so o container. }
  TDI.Registrar<IRepositorioClientes>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioClientesFB.Create(TDI.Resolver<IConexaoBanco>(C));
    end);
  TDI.Registrar<IRepositorioProdutos>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioProdutosFB.Create(TDI.Resolver<IConexaoBanco>(C));
    end);
  TDI.Registrar<IRepositorioPedidos>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioPedidosFB.Create(TDI.Resolver<IConexaoBanco>(C));
    end);
  TDI.Registrar<IRepositorioMovimentos>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioMovimentosFB.Create(TDI.Resolver<IConexaoBanco>(C));
    end);
  TDI.Registrar<IRepositorioPagamentos>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioPagamentosFB.Create(TDI.Resolver<IConexaoBanco>(C));
    end);
  TDI.Registrar<IRepositorioCentros>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioCentrosFB.Create(TDI.Resolver<IConexaoBanco>(C));
    end);
  TDI.Registrar<IRepositorioEstruturas>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioEstruturasFB.Create(TDI.Resolver<IConexaoBanco>(C));
    end);
  TDI.Registrar<IRepositorioRoteiros>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioRoteirosFB.Create(TDI.Resolver<IConexaoBanco>(C));
    end);
  TDI.Registrar<IRepositorioOrdens>(FContainer,
    function(const C: IContainer): IInterface
    begin
      Result := TRepositorioOrdensFB.Create(TDI.Resolver<IConexaoBanco>(C));
    end);
end;

procedure TAplicacao.RegistrarAssinaturas;
var
  LMural: TStringList;
  LLogger: ILogger;
begin
  LMural := FMural;
  LLogger := FLogger;

  { ATENCAO A UM CICLO SUTIL (custou um vazamento real neste projeto):

    Todo metodo anonimo aninhado guarda uma referencia ao "frame" (as variaveis
    locais) do metodo onde foi escrito -- mesmo que nao use nenhuma delas.
    Se guardassemos o barramento numa variavel local aqui (LBus := Eventos),
    teriamos:  barramento -> closure -> frame -> LBus -> barramento.
    Ciclo fechado: o barramento nunca morreria.

    Por isso chamamos Eventos (a funcao) diretamente em cada assinatura: o
    resultado e um temporario, nao entra no frame capturado.
    Verifique com "GestaoComercial.exe --demo --vazamentos". }

  // 1) Assinante "curinga": registra TODO evento no mural.
  TEventos.Assinar<TEventoDominio>(Eventos,
    procedure(AEvento: TEventoDominio)
    begin
      LMural.Add(Format('%s  %s',
        [FormatDateTime('hh:nn:ss', AEvento.OcorridoEm), AEvento.Descricao]));
      while LMural.Count > 100 do
        LMural.Delete(0);
    end, 'mural');

  // 2) Estoque baixo -> aviso para o comprador.
  TEventos.Assinar<TEstoqueBaixo>(Eventos,
    procedure(AEvento: TEstoqueBaixo)
    begin
      LLogger.Aviso('COMPRAS: repor %s (%s). Saldo %d, minimo %d.',
        [AEvento.Codigo, AEvento.DescricaoProduto, AEvento.Saldo, AEvento.Minimo]);
    end, 'compras');

  // 3) Pedido confirmado -> "envia e-mail" (aqui so loga).
  TEventos.Assinar<TPedidoConfirmado>(Eventos,
    procedure(AEvento: TPedidoConfirmado)
    begin
      LLogger.Info('E-MAIL: confirmacao do pedido %s (%s) enviada ao cliente.',
        [AEvento.Numero, TFmt.Moeda(AEvento.Total)]);
    end, 'email-confirmacao');

  // 4) Limite estourado -> alerta do financeiro.
  TEventos.Assinar<TLimiteCreditoExcedido>(Eventos,
    procedure(AEvento: TLimiteCreditoExcedido)
    begin
      LLogger.Aviso('FINANCEIRO: %s tentou comprar %s com apenas %s disponivel.',
        [AEvento.NomeCliente, TFmt.Moeda(AEvento.Solicitado),
         TFmt.Moeda(AEvento.Limite)]);
    end, 'financeiro');

  // 5) Pagamento aprovado -> baixa no contas a receber.
  TEventos.Assinar<TPagamentoAprovado>(Eventos,
    procedure(AEvento: TPagamentoAprovado)
    begin
      LLogger.Info('CONTAS A RECEBER: baixa de %s no pedido %d.',
        [TFmt.Moeda(AEvento.Valor), AEvento.PedidoId]);
    end, 'contas-receber');
end;

function TAplicacao.Clientes: IRepositorioClientes;
begin
  Result := TDI.Resolver<IRepositorioClientes>(FContainer);
end;

function TAplicacao.Produtos: IRepositorioProdutos;
begin
  Result := TDI.Resolver<IRepositorioProdutos>(FContainer);
end;

function TAplicacao.Pedidos: IRepositorioPedidos;
begin
  Result := TDI.Resolver<IRepositorioPedidos>(FContainer);
end;

function TAplicacao.Movimentos: IRepositorioMovimentos;
begin
  Result := TDI.Resolver<IRepositorioMovimentos>(FContainer);
end;

function TAplicacao.Pagamentos: IRepositorioPagamentos;
begin
  Result := TDI.Resolver<IRepositorioPagamentos>(FContainer);
end;

function TAplicacao.Vendas: IServicoVendas;
begin
  Result := TDI.Resolver<IServicoVendas>(FContainer);
end;

function TAplicacao.Estoque: IServicoEstoque;
begin
  Result := TDI.Resolver<IServicoEstoque>(FContainer);
end;

function TAplicacao.Eventos: IEventBus;
begin
  Result := TDI.Resolver<IEventBus>(FContainer);
end;

function TAplicacao.Armazenamento: IArmazenamento;
begin
  Result := TDI.Resolver<IArmazenamento>(FContainer);
end;

function TAplicacao.Politica: IPoliticaDesconto;
begin
  Result := TDI.Resolver<IPoliticaDesconto>(FContainer);
end;

function TAplicacao.UoW: IUnitOfWork;
begin
  Result := TDI.Resolver<IUnitOfWork>(FContainer);
end;

function TAplicacao.Centros: IRepositorioCentros;
begin
  Result := TDI.Resolver<IRepositorioCentros>(FContainer);
end;

function TAplicacao.Estruturas: IRepositorioEstruturas;
begin
  Result := TDI.Resolver<IRepositorioEstruturas>(FContainer);
end;

function TAplicacao.Roteiros: IRepositorioRoteiros;
begin
  Result := TDI.Resolver<IRepositorioRoteiros>(FContainer);
end;

function TAplicacao.Ordens: IRepositorioOrdens;
begin
  Result := TDI.Resolver<IRepositorioOrdens>(FContainer);
end;

function TAplicacao.Engenharia: IServicoEngenharia;
begin
  Result := TDI.Resolver<IServicoEngenharia>(FContainer);
end;

function TAplicacao.Producao: IServicoProducao;
begin
  Result := TDI.Resolver<IServicoProducao>(FContainer);
end;

function TAplicacao.UsaBanco: Boolean;
begin
  Result := FModo = mpFirebird;
end;

function TAplicacao.Banco: IConexaoBanco;
begin
  if FModo <> mpFirebird then
    Exit(nil);
  Result := TDI.Resolver<IConexaoBanco>(FContainer);
end;

function TAplicacao.Mural: TArray<string>;
begin
  Result := FMural.ToStringArray;
end;

procedure TAplicacao.LimparMural;
begin
  FMural.Clear;
end;

function TAplicacao.LinhasDeLog: TArray<string>;
begin
  if Assigned(FLogMemoria) then
    Result := FLogMemoria.Linhas
  else
    Result := nil;
end;

end.
