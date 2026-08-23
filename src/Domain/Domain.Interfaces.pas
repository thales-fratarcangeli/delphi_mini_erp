{*******************************************************************************
  Domain.Interfaces

  Os CONTRATOS que o dominio exige da infraestrutura.

  ESTUDO - Principio da Inversao de Dependencia (o "D" de SOLID):
    O dominio NAO depende de "banco de dados", "arquivo JSON" ou "memoria".
    Ele declara: "preciso de alguem que saiba guardar e buscar clientes".
    A camada Infra e quem se submete a esse contrato.

    Consequencia pratica: para testar os servicos, basta implementar estas
    interfaces com fakes em memoria - nenhum banco necessario.

  Repare tambem:
    * IRepositorio<T> e generico e SEM GUID (interfaces genericas nao podem
      ser resolvidas por QueryInterface)
    * Os repositorios especificos herdam do generico e ganham GUID, para
      poderem circular pelo container de injecao de dependencia
*******************************************************************************}
unit Domain.Interfaces;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Domain.Entities,
  Domain.Enums,
  Domain.Producao,
  Domain.Specifications;

type
  { Contrato generico de persistencia.
    ATENCAO a posse dos objetos:
      * Adicionar  -> o repositorio passa a ser o DONO da entidade
      * PorId/Todos-> devolvem referencias VIVAS (nao destrua por fora!) }
  IRepositorio<T: TEntidade> = interface
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

  IRepositorioClientes = interface(IRepositorio<TCliente>)
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D10}']
    function PorDocumento(const ADocumento: string): TCliente;
    function PorCategoria(ACategoria: TCategoriaCliente): TArray<TCliente>;
  end;

  IRepositorioProdutos = interface(IRepositorio<TProduto>)
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D11}']
    function PorCodigo(const ACodigo: string): TProduto;
    function AbaixoDoMinimo: TArray<TProduto>;
    function Categorias: TArray<string>;
  end;

  IRepositorioPedidos = interface(IRepositorio<TPedido>)
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D12}']
    function PorNumero(const ANumero: string): TPedido;
    function DoCliente(AClienteId: Integer): TArray<TPedido>;
    function ComStatus(const AStatus: TStatusPedidoSet): TArray<TPedido>;
    function ProximoNumero: string;
    /// Soma dos pedidos em aberto do cliente (usado no limite de credito).
    function TotalEmAbertoDoCliente(AClienteId: Integer): Currency;
  end;

  IRepositorioMovimentos = interface(IRepositorio<TMovimentoEstoque>)
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D13}']
    function DoProduto(AProdutoId: Integer): TArray<TMovimentoEstoque>;
  end;

  IRepositorioPagamentos = interface(IRepositorio<TPagamento>)
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D14}']
    function DoPedido(APedidoId: Integer): TArray<TPagamento>;
  end;

  { ==========================================================================
    REPOSITORIOS DO PCP
    ========================================================================== }

  IRepositorioCentros = interface(IRepositorio<TCentroTrabalho>)
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D20}']
    function PorCodigo(const ACodigo: string): TCentroTrabalho;
    function Ativos: TArray<TCentroTrabalho>;
  end;

  /// Estrutura de produto (BOM). Cada registro e UMA linha da receita.
  IRepositorioEstruturas = interface(IRepositorio<TItemEstrutura>)
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D21}']
    /// A receita de um item (seus componentes diretos, 1 nivel).
    function DoProdutoPai(AProdutoPaiId: Integer): TArray<TItemEstrutura>;
    /// "Onde e usado": em quais receitas este componente aparece.
    function OndeEUsado(AComponenteId: Integer): TArray<TItemEstrutura>;
    function Linha(AProdutoPaiId, AComponenteId: Integer): TItemEstrutura;
  end;

  IRepositorioRoteiros = interface(IRepositorio<TOperacaoRoteiro>)
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D22}']
    /// Operacoes do produto, ja em ordem de sequencia.
    function DoProduto(AProdutoId: Integer): TArray<TOperacaoRoteiro>;
    function Operacao(AProdutoId, ASequencia: Integer): TOperacaoRoteiro;
  end;

  IRepositorioOrdens = interface(IRepositorio<TOrdemProducao>)
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D23}']
    function PorNumero(const ANumero: string): TOrdemProducao;
    function ComStatus(const AStatus: TStatusOPSet): TArray<TOrdemProducao>;
    function DoProduto(AProdutoId: Integer): TArray<TOrdemProducao>;
    function ProximoNumero: string;
  end;

  { --------------------------------------------------------------------------
    UNIT OF WORK

    Agrupa varias alteracoes numa unica "transacao logica". Como estamos em
    memoria, o rollback e feito por COMPENSACAO: cada operacao registra como
    se desfazer (padrao Command). Se algo falhar no meio, desfazemos tudo na
    ordem inversa.
    -------------------------------------------------------------------------- }
  IUnitOfWork = interface
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D15}']
    procedure Iniciar;
    procedure Commit;
    procedure Rollback;
    function EmTransacao: Boolean;
    /// Registra a acao compensatoria da operacao recem-executada.
    procedure RegistrarDesfazer(const ADesfazer: TProc; const ADescricao: string = '');
    function OperacoesPendentes: Integer;
    /// Executa ABloco dentro de Iniciar/Commit, com Rollback em caso de excecao.
    procedure Executar(const ABloco: TProc);
  end;

  { Servico externo simulado (gateway de pagamento).
    Existe para mostrar como isolar dependencia externa atras de interface:
    em teste, injetamos uma versao que sempre aprova ou sempre recusa. }
  IGatewayPagamento = interface
    ['{6C0A2B31-0F2E-4E2A-9E1B-8B7C4E5A1D16}']
    function Autorizar(AValor: Currency; AForma: TFormaPagamento;
      out AAutorizacao: string): Boolean;
    function Nome: string;
  end;

implementation

end.
